from dotenv import load_dotenv
from openai import OpenAI
import json
import os
import requests
from pypdf import PdfReader
import gradio as gr
import boto3
from pathlib import Path

def load_openai_key_from_ssm():
    param = os.environ.get("SSM_OPENAI_KEY_PARAM")
    region = os.environ.get("AWS_REGION")
    if not param or not region:
        return

    ssm = boto3.client("ssm", region_name=region)
    val = ssm.get_parameter(Name=param, WithDecryption=True)["Parameter"]["Value"]
    os.environ["OPENAI_API_KEY"] = val

def load_pushover_credentials_from_ssm():
    token_param = os.environ.get("SSM_PUSHOVER_TOKEN_PARAM")
    user_param = os.environ.get("SSM_PUSHOVER_USER_PARAM")
    region = os.environ.get("AWS_REGION")
    if not token_param or not user_param or not region:
        return

    ssm = boto3.client("ssm", region_name=region)
    token_val = ssm.get_parameter(Name=token_param, WithDecryption=True)["Parameter"]["Value"]
    user_val = ssm.get_parameter(Name=user_param, WithDecryption=True)["Parameter"]["Value"]
    os.environ["PUSHOVER_TOKEN"] = token_val
    os.environ["PUSHOVER_USER"] = user_val


# Load .env for local dev (optional; on AWS, keys come from SSM)
load_dotenv()


def push(text):
    """Send a Pushover notification; no-op if credentials are not configured."""
    token = os.getenv("PUSHOVER_TOKEN")
    user = os.getenv("PUSHOVER_USER")
    if not token or not user:
        return
    try:
        requests.post(
            "https://api.pushover.net/1/messages.json",
            data={"token": token, "user": user, "message": text},
            timeout=10,
        )
    except requests.RequestException:
        pass  # Don't fail the app if Pushover is unreachable


def record_user_details(email, name="Name not provided", notes="not provided"):
    push(f"Recording {name} with email {email} and notes {notes}")
    return {"recorded": "ok"}

def record_unknown_question(question):
    push(f"Recording {question}")
    return {"recorded": "ok"}

def record_feedback(feedback_text, feedback_type="general", context=""):
    """Record feedback from users and send a push notification"""
    message = f"Feedback received ({feedback_type}): {feedback_text}"
    if context:
        message += f"\nContext: {context}"
    push(message)
    return {"recorded": "ok"}


def record_book_call(name, company, email):
    """Record that a user wants to book a call and send a push notification"""
    push(f"Book a call: {name} | {company} | {email}")
    return {"recorded": "ok"}

record_user_details_json = {
    "name": "record_user_details",
    "description": "Use when a recruiter or visitor wants to get in touch: they shared an email (and optionally name/notes). Record their contact info so Nathan can follow up.",
    "parameters": {
        "type": "object",
        "properties": {
            "email": {"type": "string", "description": "The contact's email address"},
            "name": {"type": "string", "description": "The contact's name, if provided"},
            "notes": {"type": "string", "description": "Context worth recording (e.g. role, company, opportunity)"},
        },
        "required": ["email"],
        "additionalProperties": False,
    },
}

record_unknown_question_json = {
    "name": "record_unknown_question",
    "description": "Use when you cannot answer a question (missing or unclear context). Record the question so Nathan can improve the context or follow up.",
    "parameters": {
        "type": "object",
        "properties": {
            "question": {"type": "string", "description": "The question that could not be answered"},
        },
        "required": ["question"],
        "additionalProperties": False,
    },
}

record_book_call_json = {
    "name": "record_book_call",
    "description": "Use when a recruiter or contact explicitly wants to book a call with Nathan. Record name, company, and email.",
    "parameters": {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "The contact's name"},
            "company": {"type": "string", "description": "The contact's company"},
            "email": {"type": "string", "description": "The contact's email"},
        },
        "required": ["name", "company", "email"],
        "additionalProperties": False,
    },
}

record_feedback_json = {
    "name": "record_feedback",
    "description": "Use when the user gives feedback about the chat, the site, or the experience (praise, complaints, suggestions). Record it for Nathan.",
    "parameters": {
        "type": "object",
        "properties": {
            "feedback_text": {"type": "string", "description": "The feedback text"},
            "feedback_type": {
                "type": "string",
                "description": "Type of feedback",
                "enum": ["positive", "negative", "suggestion", "question", "general"],
            },
            "context": {"type": "string", "description": "Optional context (e.g. which response or topic)"},
        },
        "required": ["feedback_text"],
        "additionalProperties": False,
    },
}

tools = [{"type": "function", "function": record_user_details_json},
        {"type": "function", "function": record_unknown_question_json},
        {"type": "function", "function": record_book_call_json},
        {"type": "function", "function": record_feedback_json}]


class Me:

    def __init__(self):
        load_openai_key_from_ssm()
        load_pushover_credentials_from_ssm()
        # App identity
        self.name = "Nathan Schellink"

        # Where Terraform/user_data syncs your S3 context files
        context_dir = Path(os.environ.get("CONTEXT_LOCAL_DIR", "me")).resolve()

        # Load base context docs (all PDFs up to limit, alphabetically)
        max_pdfs = int(os.environ.get("PDF_CONTEXT_MAX_FILES", "50"))
        self.linkedin = self._load_pdfs(context_dir, max_files=max_pdfs)

        self.summary = self._load_txt(context_dir, prefer_names=[
            "summary.txt",
        ])

        # OpenAI client (key handled separately; see note below)
        self.openai = OpenAI()

    def _load_pdfs(self, context_dir: Path, max_files: int = 50) -> str:
        """Load text from all PDFs in context_dir (and subdirs), up to max_files, sorted by path."""
        text_chunks = []
        pdf_paths = sorted(context_dir.rglob("*.pdf"))[:max_files]

        for pdf_path in pdf_paths:
            try:
                reader = PdfReader(str(pdf_path))
                for page in reader.pages:
                    t = page.extract_text() or ""
                    if t.strip():
                        text_chunks.append(t)
            except Exception as e:
                text_chunks.append(f"\n[WARN] Failed reading {pdf_path.name}: {e}\n")

        return "\n\n".join(text_chunks)

    def _load_txt(self, context_dir: Path, prefer_names=None) -> str:
        prefer_names = prefer_names or []
        chunks = []

        preferred_paths = [context_dir / name for name in prefer_names]
        other_paths = sorted(p for p in context_dir.rglob("*.txt") if p not in preferred_paths)
        txt_paths = [p for p in preferred_paths if p.exists()] + other_paths

        for txt_path in txt_paths:
            try:
                chunks.append(txt_path.read_text(encoding="utf-8"))
            except Exception as e:
                chunks.append(f"\n[WARN] Failed reading {txt_path.name}: {e}\n")

        return "\n\n".join(chunks)


    def handle_tool_call(self, tool_calls):
        results = []
        for tool_call in tool_calls:
            tool_name = tool_call.function.name
            arguments = json.loads(tool_call.function.arguments)
            print(f"Tool called: {tool_name}", flush=True)
            tool = globals().get(tool_name)
            result = tool(**arguments) if tool else {}
            results.append({"role": "tool","content": json.dumps(result),"tool_call_id": tool_call.id})
        return results
    
    def system_prompt(self):
        return (
            f"You are a representative of {self.name}, acting as the first point of contact for recruiters and others who visit his site. "
            "Your goals are to: (1) answer questions about his background, experience, and skills using the context below; "
            "(2) filter and qualify interest—especially from recruiters—so only relevant opportunities reach him; "
            "(3) get interested, qualified contacts in touch by capturing their email (record_user_details) or booking a call (record_book_call). "
            "Be professional and concise. Represent him faithfully. "
            "When you don't know an answer, use record_unknown_question so he can improve the context. "
            "When someone gives feedback on the chat or site, use record_feedback. "
            "When a recruiter or visitor wants to connect, encourage them to share their email or book a call (e.g. https://calendar.app.google/S8u5pxaknnFtAmxZ6) and use the appropriate tool. "
            "The summary may include job-filtering preferences marked 'Do not share with user'. Use these only to evaluate fit internally; never quote or reveal them. "
            "Politely decline opportunities that don't match those criteria without stating the exact requirements."
            f"\n\n## Summary\n{self.summary}\n\n## Resume / profile / documents\n{self.linkedin}\n\n"
            "Stay in character as Nathan's representative. Be helpful and direct recruiters toward next steps when there's a fit."
        )

    def get_welcome_message(self):
        return (
            f"Hi! I represent **{self.name}**. I'm here to answer questions about his background, experience, and career—and to help connect you with him if there's a fit.\n\n"
            "Ask me anything about his skills, roles, or preferences. If you're a recruiter with a relevant opportunity and would like to get in touch, I can capture your details or point you to his calendar to book a call.\n\n"
            "How can I help you today?"
        )
    
    def chat(self, message, history):
        messages = [{"role": "system", "content": self.system_prompt()}]
        messages.extend(history)
        messages.append({"role": "user", "content": message})

        try:
            done = False
            while not done:
                response = self.openai.chat.completions.create(
                    model="gpt-4o-mini", messages=messages, tools=tools
                )
                if response.choices[0].finish_reason == "tool_calls":
                    msg = response.choices[0].message
                    results = self.handle_tool_call(msg.tool_calls)
                    messages.append(msg)
                    messages.extend(results)
                else:
                    done = True
            return response.choices[0].message.content or ""
        except Exception as e:
            print(f"OpenAI API error: {e}", flush=True)
            return "Sorry, something went wrong on my side. Please try again or get in touch directly if you'd like to connect."
    

if __name__ == "__main__":
    me = Me()
    welcome_message = me.get_welcome_message()
    # Show welcome message when chat opens by pre-populating the chatbot
    chatbot = gr.Chatbot(
        value=[{"role": "assistant", "content": welcome_message}],
        type="messages",
    )
    with gr.Blocks(title=f"Chat with {me.name}") as demo:
        gr.Markdown(f"## Chat with {me.name}")
        gr.Markdown(
            "**For recruiters:** Learn about Nathan's background and see if there's a fit. "
            "Interested in connecting? Share your details and I'll make sure he gets in touch."
        )
        gr.ChatInterface(me.chat, chatbot=chatbot, type="messages")
    # Bind to all interfaces for container/EC2; port from env or default 7860
    demo.launch(
        server_name=os.environ.get("GRADIO_SERVER_NAME", "0.0.0.0"),
        server_port=int(os.environ.get("GRADIO_SERVER_PORT", "7860")),
    )
    