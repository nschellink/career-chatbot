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

# load_dotenv(override=True)


def push(text):
    requests.post(
        "https://api.pushover.net/1/messages.json",
        data={
            "token": os.getenv("PUSHOVER_TOKEN"),
            "user": os.getenv("PUSHOVER_USER"),
            "message": text,
        }
    )


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
    "description": "Use this tool to record that a user is interested in being in touch and provided an email address",
    "parameters": {
        "type": "object",
        "properties": {
            "email": {
                "type": "string",
                "description": "The email address of this user"
            },
            "name": {
                "type": "string",
                "description": "The user's name, if they provided it"
            }
            ,
            "notes": {
                "type": "string",
                "description": "Any additional information about the conversation that's worth recording to give context"
            }
        },
        "required": ["email"],
        "additionalProperties": False
    }
}

record_unknown_question_json = {
    "name": "record_unknown_question",
    "description": "Always use this tool to record any question that couldn't be answered as you didn't know the answer",
    "parameters": {
        "type": "object",
        "properties": {
            "question": {
                "type": "string",
                "description": "The question that couldn't be answered"
            },
        },
        "required": ["question"],
        "additionalProperties": False
    }
}

record_book_call_json = {
    "name": "record_book_call",
    "description": "Always use this tool to record that a user wants to book a call with you",
    "parameters": {
        "type": "object",
        "properties": {
            "name": {
                "type": "string",
                "description": "The user's name"
            },
            "company": {
                "type": "string",
                "description": "The user's company"
            },
            "email": {
                "type": "string",
                "description": "The user's email"
            },
        },
        "required": ["name", "company", "email"],
        "additionalProperties": False
    }
}

record_feedback_json = {
    "name": "record_feedback",
    "description": "Use this tool to record any feedback, comments, complaints, praise, or suggestions that users provide about the chat experience, responses, or website. Always use this when a user expresses satisfaction, dissatisfaction, suggestions, or any form of feedback.",
    "parameters": {
        "type": "object",
        "properties": {
            "feedback_text": {
                "type": "string",
                "description": "The feedback text provided by the user"
            },
            "feedback_type": {
                "type": "string",
                "description": "The type of feedback: 'positive', 'negative', 'suggestion', 'question', or 'general'",
                "enum": ["positive", "negative", "suggestion", "question", "general"]
            },
            "context": {
                "type": "string",
                "description": "Optional context about what the feedback relates to (e.g., which response, topic, or feature)"
            }
        },
        "required": ["feedback_text"],
        "additionalProperties": False
    }
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

        # Load base context docs
        self.linkedin = self._load_pdfs(context_dir, prefer_names=[
            "Profile.pdf",
            "Resume_NathanSchellink_2026.pdf",
        ])

        self.summary = self._load_txt(context_dir, prefer_names=[
            "summary.txt",
        ])

        # OpenAI client (key handled separately; see note below)
        self.openai = OpenAI()

    def _load_pdfs(self, context_dir: Path, prefer_names=None) -> str:
        prefer_names = prefer_names or []
        text_chunks = []

        # Read preferred PDFs first (if present), then any other PDFs
        preferred_paths = [context_dir / name for name in prefer_names]
        other_paths = sorted(p for p in context_dir.rglob("*.pdf") if p not in preferred_paths)
        pdf_paths = [p for p in preferred_paths if p.exists()] + other_paths

        for pdf_path in pdf_paths:
            try:
                reader = PdfReader(str(pdf_path))
                for page in reader.pages:
                    t = page.extract_text() or ""
                    if t.strip():
                        text_chunks.append(t)
            except Exception as e:
                # Don't crash app if one PDF is malformed
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
        system_prompt = f"You are acting as {self.name}. You are answering questions on {self.name}'s website, \
        particularly questions related to {self.name}'s career, background, skills and experience. \
        Your responsibility is to represent {self.name} for interactions on the website as faithfully as possible. \
        You are given a summary of {self.name}'s background, resume, and LinkedIn profile which you can use to answer questions. \
        Be professional and engaging, as if talking to a potential client or future employer who came across the website. \
        If you don't know the answer to any question, use your record_unknown_question tool to record the question that you couldn't answer, even if it's about something trivial or unrelated to career. \
        If the user is engaging in discussion, try to steer them towards getting in touch via email; ask for their email and record it using your record_user_details tool. Alternatively, you can direct them to book a call with me: https://calendar.app.google/S8u5pxaknnFtAmxZ6 \
        If a user provides any feedback, comments, suggestions, complaints, or expresses satisfaction or dissatisfaction with the chat experience or your responses, always use your record_feedback tool to record it. This includes positive feedback, negative feedback, suggestions for improvement, or any comments about the website or chat functionality."

        system_prompt += f"\n\n## Summary:\n{self.summary}\n\n## LinkedIn Profile:\n{self.linkedin}\n\n"
        system_prompt += f"With this context, please chat with the user, always staying in character as {self.name}. "
        system_prompt += f"IMPORTANT: The summary contains job filtering preferences marked 'Do not share with user' - use these preferences internally to filter and evaluate job opportunities, but NEVER directly quote or share these specific preferences (salary requirements, location preferences, work type preferences, etc.) with users. Instead, politely decline opportunities that don't match these criteria without revealing the specific requirements."
        return system_prompt

    def get_welcome_message(self):
        return f"Hello! I'm {self.name}. Hi, I represent Nathan Schellink! It's great to meet you! I'm here to answer any questions you might have about my background, experience, skills, or career. Feel free to ask me anything, and if you'd like to get in touch, I'd be happy to connect!\n\nHow can I help you today?"
    
    def chat(self, message, history):
        # Build messages list
        messages = [{"role": "system", "content": self.system_prompt()}]
        messages.extend(history)
        messages.append({"role": "user", "content": message})
        
        # Process the conversation
        done = False
        while not done:
            response = self.openai.chat.completions.create(model="gpt-4o-mini", messages=messages, tools=tools)
            if response.choices[0].finish_reason=="tool_calls":
                message = response.choices[0].message
                tool_calls = message.tool_calls
                results = self.handle_tool_call(tool_calls)
                messages.append(message)
                messages.extend(results)
            else:
                done = True
        
        return response.choices[0].message.content
    

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
        gr.Markdown("Welcome! I'm here to answer questions about my background, experience, and career. Feel free to ask me anything!")
        gr.ChatInterface(me.chat, chatbot=chatbot, type="messages")
    # Bind to all interfaces for container/EC2; port from env or default 7860
    demo.launch(
        server_name=os.environ.get("GRADIO_SERVER_NAME", "0.0.0.0"),
        server_port=int(os.environ.get("GRADIO_SERVER_PORT", "7860")),
    )
    