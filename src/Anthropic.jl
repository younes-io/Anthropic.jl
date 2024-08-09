module Anthropic

using HTTP
using JSON

export stream_response

const API_URL = "https://api.anthropic.com/v1/messages"

function get_api_key()
    key = get(ENV, "ANTHROPIC_API_KEY", "")
    isempty(key) && error("ANTHROPIC_API_KEY environment variable is not set")
    return key
end

stream_response(prompt::String; model::String="claude-3-5-sonnet-20240620", max_tokens::Int=256) = stream_response([Dict("role" => "user", "content" => prompt)]; model, max_tokens)
function stream_response(msgs::Vector{Dict{String,String}}; model::String="claude-3-opus-20240229", max_tokens::Int=1024)
    body = Dict("model" => model, "max_tokens" => max_tokens, "stream" => true)
    
    if msgs[1]["role"] == "system"
        body["system"] = msgs[1]["content"]
        body["messages"] = msgs[2:end]
    else
        body["messages"] = msgs
    end
    headers = [
        "Content-Type" => "application/json",
        "X-API-Key" => get_api_key(),
        "anthropic-version" => "2023-06-01"
    ]
    
    channel = Channel{String}(128)
    @async_showerr (
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
                    # TODO !!! type == error !! HANDLE!!
                    startswith(line, "data: ") || continue
                    line == "data: [DONE]" && (isdone=true; break)
                    data = JSON.parse(replace(line, r"^data: " => ""))
                    # @show data
                    get(data, "type", "") == "error" && (print(data["error"]); (isdone=true); break)
                    if get(get(data, "delta", Dict()), "type", "") == "text_delta"
                        text = data["delta"]["text"]
                        put!(channel, text)
                        # print(output, text)
                        print(text)
                        flush(stdout)
                    end
                end
            end
            HTTP.closeread(io)
        end;
    )

    return channel
end

end # module Anthropic
