# New parsing functions
parse_text_delta(data) = return get(get(data, "delta", Dict()), "text", "")

function parse_message_start(data, start_time_usr)
    message = get(data, "message", Dict())
    usage = get(message, "usage", Dict())
    return Dict(
        "id" => get(message, "id", ""),
        "elapsed" => time() - start_time_usr,
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0),
    )
end

function parse_message_delta(data, start_time_ai)
    usage = get(data, "usage", Dict())
    @show start_time_ai
    @show time()-start_time_ai
    return Dict(
        "elapsed" => time()-start_time_ai,
        "input_tokens"  => get(usage, "input_tokens",  0),
        "output_tokens" => get(usage, "output_tokens", 0),
        "cache_creation_input_tokens" => get(usage, "cache_creation_input_tokens", 0),
        "cache_read_input_tokens"     => get(usage, "cache_read_input_tokens",     0)
    )
end

function parse_error(data)
    error = get(data, "error", Dict())
    return Dict(
        "type"    => get(error, "type",    "unknown"),
        "message" => get(error, "message", "Unknown error"),
        "details" => get(error, "details", "")
    )
end

function parse_stream_data(raw_data::String)
    start_time_usr=time()
    start_time_ai=0
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
            # println(data)

            if state == :message_start
                push!(events, (:meta_usr, parse_message_start(data, start_time_usr)))
                start_time_ai = time()
            elseif state == :message_delta
                push!(events, (:meta_ai,  parse_message_delta(data, start_time_ai)))
            elseif state == :content_block_delta
                push!(events, (:text, parse_text_delta(data)))
            elseif state == :ping
            elseif state in [:content_block_start, :content_block_stop, :message_stop]
                nothing # unuseful data actually...
            elseif state == :error
                push!(events, (:error, parse_error(data)))
            else
                @warn "unhandled eventype: $state \n$data"
            end
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
    full_response = ""
    user_meta = Dict()
    ai_meta = Dict()
    
    for chunk in channel
        for (type, content) in parse_stream_data(chunk)
            if type == :text
                full_response *= content
                on_text(content)
            elseif type == :meta_usr
                user_meta = append_calculated_cost(content, model)
                on_meta_usr(user_meta)
            elseif type == :meta_ai
                ai_meta = append_calculated_cost(content, model)
                on_meta_ai(ai_meta)
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

function channel_to_string(channel::Channel; cb=(()-> return nothing))
    first_text = take!(channel)
    response = first_text
    cb()
    println()
    print("\e[32m¬ \e[0m")
    print(first_text)
    for chunk in channel
        response *= chunk
        print(chunk)
    end
    return response
end

