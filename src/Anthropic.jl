module Anthropic

using HTTP
using JSON
using BoilerplateCvikli: @async_showerr
using PromptingTools: SystemMessage, UserMessage, AIMessage

const API_URL = "https://api.anthropic.com/v1/messages"
const DEFAULT_MAX_TOKEN = 4096

include("error_handler.jl")
include("pricing.jl")
include("parser.jl")

export ai_stream_safe, ai_ask_safe, stream_response, process_stream

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

function convert_user_messages(msgs::Vector{Dict{String,String}})
    return [
        if msg["role"] == "user"
            Dict("role" => "user",
                 "content" => [Dict{String, Any}("type" => "text", "text" => msg["content"])])
        else
            msg
        end
        for msg in msgs
    ]
end

function anthropic_extra_headers(; has_tools = false, has_cache = false, max_tokens_extended = false)
    extra_headers = ["anthropic-version" => "2023-06-01"]
    beta_features = String[]
    has_tools && push!(beta_features, "tools-2024-04-04")
    has_cache && push!(beta_features, "prompt-caching-2024-07-31")
    max_tokens_extended && push!(beta_features, "max-tokens-3-5-sonnet-2024-07-15")
    !isempty(beta_features) && push!(extra_headers, "anthropic-beta" => join(beta_features, ","))
    return extra_headers
end

stream_response(prompt::String;                    system_msg="", model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false, cache::Union{Nothing,Symbol}=nothing) = stream_response([Dict("role" => "user", "content" => prompt)]; system_msg, model, max_tokens, printout, verbose, cache)
stream_response(msgs::Vector{Dict{String,String}}; system_msg="", model::String="claude-3-5-sonnet-20240620", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false, cache::Union{Nothing,Symbol}=nothing) = begin
    body = Dict("messages" => convert_user_messages(msgs), "model" => model, "max_tokens" => max_tokens, "stream" => true)
    @assert is_valid_message_sequence(body["messages"]) "Invalid message sequence. Messages should alternate between 'user' and 'assistant', starting with 'user'. $(msgs[2:end])"
    
    !isempty(system_msg) && (body["system"] = system_msg)
    
    headers = [
        "Content-Type" => "application/json",
        "X-API-Key" => get_api_key(),
    ]
    
    # Add anthropic-beta header if needed
    extra_headers = anthropic_extra_headers(
        has_cache = !isnothing(cache),
        max_tokens_extended = (max_tokens > 4096 && model == "claude-3-5-sonnet-20240620")
    )
    append!(headers, extra_headers)
    
    # Apply cache control if specified
    if !isnothing(cache)
        # Apply cache control to all messages if cache is :last or :all
        if cache == :last || cache == :all
            for msg in body["messages"][max(end-2, 1):end]
                if msg["role"] == "user" && !isempty(msg["content"])
                    msg["content"][end]["cache_control"] = Dict("type" => "ephemeral")
                end
            end
        end
        
        # Apply cache control to the system message if present
        if (cache == :system || cache == :all) && haskey(body, "system")
            body["system"] = [Dict("type" => "text", "text" => body["system"], "cache_control" => Dict("type" => "ephemeral"))]
        end
    end
    
    channel = Channel{String}(2000)
    @async_showerr (
        HTTP.open("POST", "https://api.anthropic.com/v1/messages", headers; status_exception=false) do io
            write(io, JSON.json(body))
            HTTP.closewrite(io)
            HTTP.startread(io) 
            while !eof(io)
                chunk = String(readavailable(io))
                put!(channel, chunk)
                printout && (print(chunk); flush(stdout))
            end
            HTTP.closeread(io)
        end;
        isopen(channel) && close(channel);
    )

    return channel
end


ai_stream_safe(msgs; model, max_tokens=DEFAULT_MAX_TOKEN, printout=true, system_msg="", cache=nothing) = stream_response(msgs; system_msg, model, max_tokens, printout, cache)
ai_ask_safe(conversation::Vector{Dict{String,String}}; model, return_all=false, max_token=DEFAULT_MAX_TOKEN, cache=nothing)     = safe_fn(aigenerate, 
 [
    msg["role"] == "system" ? SystemMessage(msg["content"]) :
    msg["role"] == "user" ? UserMessage(msg["content"]) :
    msg["role"] == "assistant" ? AIMessage(msg["content"]) : UserMessage(msg["content"])
    for msg in conversation
]; model, return_all, max_token, cache)
ai_ask_safe(conversation; model, return_all=false, max_token=DEFAULT_MAX_TOKEN, cache=nothing)     = safe_fn(aigenerate, conversation; model, return_all, max_token, cache)

end # module Anthropic
