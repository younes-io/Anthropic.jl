# New parsing functions
parse_text_delta(data) = return get(get(data, "delta", Dict()), "text", "")

function parse_message_start(data, model)
    message = get(data, "message", Dict())
    usage = get(message, "usage", Dict())
    data = Dict{String,Any}(
        "id" => get(message, "id", ""),
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0),
    )
    data["price"] = append_calculated_cost(data, model)
    return data
end

function parse_message_delta(data, model)
    usage = get(data, "usage", Dict())
    data = Dict{String,Any}(
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0)
    )
    data["price"] = append_calculated_cost(data, model)
    return data
end

function parse_error(data)
    error = get(data, "error", Dict())
    return Dict(
        "type"    => get(error, "type",    "unknown"),
        "message" => get(error, "message", "Unknown error"),
        "details" => get(error, "details", "")
    )
end

function parse_stream_data(raw_data::String, model)
    events = []
    lines = split(raw_data, '\n')
    state = :waiting

    for line in lines
        isempty(line) && continue
# @show line
        if startswith(line, "event: ")
            state = Symbol(strip(line[8:end]))
        elseif startswith(line, "data: ")
            dat = line[6:end]
            if line == "[DONE]"
                push!(events, (:done, nothing))
                break
            end

            data = try
                JSON.parse(dat)
            catch e
                @warn "Failed to parse JSON: $line" exception=(e, catch_backtrace())
                push!(events, (:error, "Failed to parse JSON: $line"))
                continue
            end
            if state == :message_start
                push!(events, (:meta_usr, parse_message_start(data, model)))
            elseif state == :message_delta
                push!(events, (:meta_ai,  parse_message_delta(data, model)))
            elseif state == :content_block_delta
                push!(events, (:text, parse_text_delta(data)))
            elseif state == :ping
                push!(events, (:ping, ""))
            elseif state in [:content_block_start, :content_block_stop, :message_stop]
                nothing # unuseful data actually...
            elseif state == :error
                push!(events, (:error, parse_error(data)))
            else
                @warn "unhandled eventype: $state\n$data"
            end
        else
            @assert false "$line"
        end
    end
    return events
end

function process_stream(channel::Channel, model;
    on_text::Function     = (text) -> print(text),
    on_meta_usr::Function = (meta) -> nothing,
    on_meta_ai::Function  = (meta) -> nothing,
    on_error::Function    = (error) -> @warn("Error in stream: $error"),
    on_done::Function     = () -> @debug("Stream finished")
)
    start_time = time()
    start_time_usr=0
    start_time_ai=0
    full_response = ""
    user_meta = Dict()
    ai_meta = Dict()
    
    for chunk in channel
        for (type, content) in parse_stream_data(chunk, model)
            if type == :text
                full_response *= content
                on_text(content)
            elseif type == :meta_usr
                start_time_usr = time()
                user_meta=content
                user_meta["elapsed"] = start_time_usr-start_time
                on_meta_usr(user_meta)
            elseif type == :meta_ai
                start_time_ai  = time()
                ai_meta=content
                ai_meta["elapsed"] = start_time_ai-start_time_usr
                on_meta_ai(ai_meta)
            elseif type == :ping
                # start_time = time()
            elseif type == :error
                on_error(content)
            elseif type == :done
                on_done()
                break
            end
        end
    end
    return full_response, user_meta, ai_meta
end

