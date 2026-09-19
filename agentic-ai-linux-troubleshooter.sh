#!/usr/bin/env bash

###############################################################################
# Linux AI Assistant
#
# Bash + Ollama Cloud
#
# Purpose:
#   A simple AI-powered Linux/DevOps assistant.
#
#   The LLM can request READ-ONLY Linux diagnostic commands.
#   Bash validates the requested command before executing it.
#
# Requirements:
#   bash
#   curl
#   jq
#
# Environment:
#   export OLLAMA_API_KEY="your-api-key"
#   export OLLAMA_MODEL="gpt-oss:120b"
#
###############################################################################

set -u

OLLAMA_URL="https://ollama.com/api/chat"
MODEL="${OLLAMA_MODEL:-gpt-oss:120b}"

if [[ -z "${OLLAMA_API_KEY:-}" ]]; then
    echo "ERROR: OLLAMA_API_KEY is not set."
    echo
    echo "Example:"
    echo 'export OLLAMA_API_KEY="your-api-key"'
    exit 1
fi

SYSTEM_PROMPT='
You are a Linux and DevOps troubleshooting assistant.

Your job is to help troubleshoot Linux systems.

You have access to a limited set of READ-ONLY diagnostic tools.

Important rules:

1. Never suggest destructive commands.
2. Never request rm, mv, chmod, chown, kill, reboot, shutdown,
   systemctl restart, systemctl stop or similar commands.
3. Use diagnostic tools when actual system information is required.
4. Explain what the command output means.
5. Do not assume the problem. Check the system first when appropriate.
6. Keep explanations practical and easy to understand.
7. If a problem cannot be confirmed from the available information,
   clearly say what additional information is required.
'

###############################################################################
# Tool definition
###############################################################################

TOOLS='[
  {
    "type": "function",
    "function": {
      "name": "run_linux_diagnostic",
      "description": "Run an approved read-only Linux diagnostic command.",
      "parameters": {
        "type": "object",
        "properties": {
          "command": {
            "type": "string",
            "description": "Approved Linux diagnostic command"
          }
        },
        "required": ["command"]
      }
    }
  }
]'

###############################################################################
# Conversation history
###############################################################################

MESSAGES="[]"

###############################################################################
# Validate command before execution
###############################################################################

validate_command() {

    local cmd="$1"

    case "$cmd" in

        "uptime")
            return 0
            ;;

        "uname -a")
            return 0
            ;;

        "df -h")
            return 0
            ;;

        "free -h")
            return 0
            ;;

        "ps aux --sort=-%cpu | head -20")
            return 0
            ;;

        "ps aux --sort=-%mem | head -20")
            return 0
            ;;

        "ss -tulpn")
            return 0
            ;;

        "du -sh /var/*")
            return 0
            ;;

        "du -sh /tmp/*")
            return 0
            ;;

        systemctl\ status\ *)
            [[ "$cmd" =~ ^systemctl[[:space:]]status[[:space:]][a-zA-Z0-9_.@-]+$ ]]
            return $?
            ;;

        journalctl\ -u\ *)
            [[ "$cmd" =~ ^journalctl[[:space:]]-u[[:space:]][a-zA-Z0-9_.@-]+[[:space:]]-n[[:space:]]50[[:space:]]--no-pager$ ]]
            return $?
            ;;

        *)
            return 1
            ;;
    esac
}

###############################################################################
# Execute approved command
###############################################################################

execute_command() {

    local cmd="$1"

    if ! validate_command "$cmd"; then

        echo "Command rejected by security policy:"
        echo "$cmd"

        return 1
    fi

    echo
    echo "----------------------------------------"
    echo "Running: $cmd"
    echo "----------------------------------------"

    # shellcheck disable=SC2086
    bash -c "$cmd"

    local rc=$?

    echo
    echo "Command exit code: $rc"

    return "$rc"
}

###############################################################################
# Ask Ollama
###############################################################################

ask_ollama() {

    local payload="$1"
    local response
    local http_code

    
    # response=$(curl -sS \
    #     #--fail-with-body \
    #     --connect-timeout 10 \
    #     --max-time 180 \
    #     "$OLLAMA_URL" \
    #     -H "Authorization: Bearer $OLLAMA_API_KEY" \
    #     -H "Content-Type: application/json" \
    #     -d "$payload")
    
    response=$(curl -sS \
        --connect-timeout 10 \
        --max-time 180 \
        -w "\n%{http_code}" \
        "$OLLAMA_URL" \
        -H "Authorization: Bearer $OLLAMA_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload")


    local rc=$?

    if [[ $rc -ne 0 ]]; then
        echo
        echo "ERROR: Ollama API request failed."
        echo "$response"
        return 1
    fi

    http_code=$(tail -n 1 <<< "$response")
    response=$(sed '$d' <<< "$response")

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        echo
        echo "ERROR: Ollama API returned HTTP $http_code"
        echo "$response"
        return 1
    fi

    printf '%s' "$response"
}

###############################################################################
# Main chat loop
###############################################################################

echo
echo "=============================================="
echo "        Linux AI / DevOps Assistant"
echo "=============================================="
echo
echo "Model : $MODEL"
echo
echo "Ask questions such as:"
echo
echo "  Why is my server running out of disk?"
echo "  Check memory usage"
echo "  Is SSH running?"
echo "  Show me the top CPU consuming processes"
echo "  Check the status of nginx"
echo
echo "Type 'exit' to quit."
echo

while true; do

    printf "\nYou: "
    IFS= read -r USER_INPUT

    [[ -z "$USER_INPUT" ]] && continue

    case "$USER_INPUT" in
        exit|quit)
            echo
            echo "Goodbye."
            break
            ;;

        clear)
            MESSAGES="[]"
            clear
            echo "Conversation cleared."
            continue
            ;;
    esac

    ###########################################################################
    # Add user message
    ###########################################################################

    MESSAGES=$(jq \
        --arg content "$USER_INPUT" \
        '. + [{"role":"user","content":$content}]' \
        <<< "$MESSAGES")

    ###########################################################################
    # Agent loop
    #
    # The model may:
    #
    # 1. Answer directly
    # 2. Request a Linux diagnostic command
    #
    ###########################################################################

    while true; do

        PAYLOAD=$(jq -n \
            --arg model "$MODEL" \
            --arg system "$SYSTEM_PROMPT" \
            --argjson messages "$MESSAGES" \
            --argjson tools "$TOOLS" \
            '{
                model: $model,
                messages: (
                    [{"role":"system","content":$system}]
                    + $messages
                ),
                tools: $tools,
                stream: false
            }')

        echo
        echo "AI is thinking..."

        RESPONSE=$(ask_ollama "$PAYLOAD")

        if [[ $? -ne 0 ]]; then
            break
        fi

        #######################################################################
        # Check whether model requested a tool
        #######################################################################

        TOOL_CALL=$(jq -c '.message.tool_calls[0] // empty' <<< "$RESPONSE")

        if [[ -n "$TOOL_CALL" ]]; then

            TOOL_NAME=$(jq -r '.function.name' <<< "$TOOL_CALL")

            COMMAND=$(jq -r \
                '.function.arguments.command // empty' \
                <<< "$TOOL_CALL")

            echo
            echo "AI requested diagnostic:"
            echo "  $COMMAND"

            if [[ "$TOOL_NAME" != "run_linux_diagnostic" ]]; then

                echo "ERROR: Unknown tool requested."
                break
            fi

            ###################################################################
            # Validate command
            ###################################################################

            if ! validate_command "$COMMAND"; then

                echo
                echo "SECURITY: Command rejected."
                echo "Only approved read-only commands are allowed."

                TOOL_RESULT="Command rejected by local security policy."

            else

                #################################################################
                # Execute command
                #################################################################

                TOOL_RESULT=$(execute_command "$COMMAND" 2>&1)

            fi

            ###################################################################
            # Add assistant tool-call message to conversation
            ###################################################################

            MESSAGES=$(jq \
                --argjson assistant "$(jq '.message' <<< "$RESPONSE")" \
                '. + [$assistant]' \
                <<< "$MESSAGES")

            ###################################################################
            # Add tool result
            ###################################################################

            MESSAGES=$(jq \
                --arg content "$TOOL_RESULT" \
                '. + [{"role":"tool","content":$content}]' \
                <<< "$MESSAGES")

            continue

        else

            ###################################################################
            # Normal assistant response
            ###################################################################

            ANSWER=$(jq -r '.message.content // empty' <<< "$RESPONSE")

            echo
            echo "AI:"
            echo
            printf '%s\n' "$ANSWER"

            ###################################################################
            # Store response in conversation
            ###################################################################

            MESSAGES=$(jq \
                --arg content "$ANSWER" \
                '. + [{"role":"assistant","content":$content}]' \
                <<< "$MESSAGES")

            break
        fi

    done

done