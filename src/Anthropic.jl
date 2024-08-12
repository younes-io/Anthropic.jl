module Anthropic

using HTTP
using JSON

const API_URL = "https://api.anthropic.com/v1/messages"
const DEFAULT_MAX_TOKEN = 1024

include("error_handler.jl")


export ai_stream_safe, ai_ask_safe, stream_response

function get_api_key()
    key = get(ENV, "ANTHROPIC_API_KEY", "")
    isempty(key) && error("ANTHROPIC_API_KEY environment variable is not set")
    return key
end

function is_valid_message_sequence(messages)
    if isempty(messages) || messages[1]["role"] != "user"
        return false
    end
    for i in 2:length(messages)
        if messages[i]["role"] == messages[i-1]["role"]
            return false
        end
        if messages[i]["role"] ∉ ["user", "assistant"]
            return false
        end
    end
    return true
end

stream_response(prompt::String; model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true) = stream_response([Dict("role" => "user", "content" => prompt)]; model, max_tokens, printout)
function stream_response(msgs::Vector{Dict{String,String}}; model::String="claude-3-opus-20240229", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true)
    body = Dict("model" => model, "max_tokens" => max_tokens, "stream" => true)
    
    if msgs[1]["role"] == "system"
        body["system"] = msgs[1]["content"]
        body["messages"] = msgs[2:end]
    else
        body["messages"] = msgs
    end
    
    @assert is_valid_message_sequence(body["messages"]) "Invalid message sequence. Messages should alternate between 'user' and 'assistant', starting with 'user'. $(msgs[2:end])"
    

    headers = [
        "Content-Type" => "application/json",
        "X-API-Key" => get_api_key(),
        "anthropic-version" => "2023-06-01"
    ]
    
    channel = Channel{String}(2000)
    meta = Channel{String}(100)
    @async (
        HTTP.open("POST", "https://api.anthropic.com/v1/messages", headers; status_exception=false) do io
            write(io, JSON.json(body))
            HTTP.closewrite(io)    # indicate we're done writing to the request
            HTTP.startread(io) 
            isdone = false
            while !eof(io) && !isdone
                chunk = String(readavailable(io))

                lines = String.(filter(!isempty, split(chunk, "\n")))
                for line in lines
                    # @show line
                    startswith(line, "data: ") || continue
                    line == "data: [DONE]" && (isdone=true; break)
                    data = JSON.parse(replace(line, r"^data: " => ""))
                    if data["type"] == "error"
                        @show line
                        error_msg = get(data, "error", Dict("message" => "Unknown error"))["message"]
                        put!(channel, "ERROR: $error_msg")
                        printout && println("\nERROR: $error_msg\n")
                        put!(channel, "Details: $(get(data["error"], "details",""))")
                        printout && println("\nERROR: $(get(data["error"], "details",""))\n")
                        isdone = true
                        break
                    elseif get(get(data, "delta", Dict()), "type", "") == "text_delta"
                        text = data["delta"]["text"]
                        put!(channel, text)
                        printout && print(text)
                        flush(stdout)                   
                    elseif data["type"] == "message_delta"
                        put!(meta, "((input_tokens: $(get(get(data,"usage",Dict()),"input_tokens",-1)), output_tokens: $(get(get(data,"usage",Dict()), "output_tokens", -1))))")
                    elseif data["type"] == "message_start"
                        put!(meta, "((message: $(get(data["message"],"id",-1)), input_tokens: $(get(get(data,"usage",Dict()),"input_tokens",-1)), output_tokens: $(get(get(data,"usage",Dict()), "output_tokens", -1))))")
                    elseif data["type"] == "message_stop"
                        close(channel)
                        close(meta)
                    elseif data["type"] in ["content_block_start", "content_block_stop", "ping"]
                        nothing
                    else
                        println("unknown packet")
                        println(line)
                    end
                end
            end
            HTTP.closeread(io)
        end;
        isopen(channel) && close(channel);
        isopen(meta) && close(meta)
    )

    return channel
end

function channel_to_string(channel::Channel)
    response = ""
    for chunk in channel
        response *= chunk
    end
    return response
end

ai_stream_safe(msgs; model, max_tokens=DEFAULT_MAX_TOKEN, printout=true) = safe_fn(stream_response, msgs, model=model, max_tokens=max_tokens, printout=printout)
ai_ask_safe(conversation; model, return_all=false)     = safe_fn(aigenerate, conversation, model=model, return_all=return_all)

end # module Anthropic
