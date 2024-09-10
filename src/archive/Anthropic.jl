function stream_response(msgs::Vector{Dict{String,String}}; system_msg="", model::String="claude-3-opus-20240229", max_tokens::Int=DEFAULT_MAX_TOKEN, printout=true, verbose=false, cache::Union{Nothing,Symbol}=nothing)
	body = Dict("messages" => convert_user_messages(msgs), "model" => model, "max_tokens" => max_tokens, "stream" => true)
	
	system_msg !== "" && (body["system"] = system_msg)
	
	@assert is_valid_message_sequence(body["messages"]) "Invalid message sequence. Messages should alternate between 'user' and 'assistant', starting with 'user'. $(msgs[2:end])"
	
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
	user_meta, ai_meta = StreamMeta(), StreamMeta()
	start_time = time()
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
									if startswith(line, "data: ") 
											line == "data: [DONE]" && (isdone=true; break)
											data = JSON.parse(replace(line, r"^data: " => ""))
											if get(get(data, "delta", Dict()), "type", "") == "text_delta"
													text = data["delta"]["text"]
													put!(channel, text)
													printout && (print(text);flush(stdout)   )                
											elseif data["type"] == "message_start"
													user_meta.elapsed       = time() # we substract start_time after message arrived!
													user_meta.id            = get(data["message"],"id","")
													user_meta.input_tokens  = get(get(data["message"],"usage",Dict()),"input_tokens",0)
													user_meta.output_tokens = get(get(data["message"],"usage",Dict()),"output_tokens",0)
													user_meta.cache_creation_input_tokens = get(get(data["message"],"usage",Dict()),"cache_creation_input_tokens",0)
													user_meta.cache_read_input_tokens = get(get(data["message"],"usage",Dict()),"cache_read_input_tokens",0)
													call_cost!(user_meta, model);
											elseif data["type"] == "message_delta"
													ai_meta.elapsed       = time() # we substract start_time after message arrived!
													ai_meta.input_tokens  = get(get(data,"usage",Dict()),"input_tokens",0)
													ai_meta.output_tokens = get(get(data,"usage",Dict()),"output_tokens",0)
													ai_meta.cache_creation_input_tokens = get(get(data,"usage",Dict()),"cache_creation_input_tokens",0)
													ai_meta.cache_read_input_tokens = get(get(data,"usage",Dict()),"cache_read_input_tokens",0)
													call_cost!(ai_meta, model);
											elseif data["type"] == "message_stop"
													close(channel)
											elseif data["type"] in ["content_block_start", "content_block_stop", "ping"]
													nothing
											elseif data["type"] == "error"
													error_type    = get(data["error"], "type", "unknown")
													error_msg     = get(data["error"], "message", "Unknown error")
													error_details = get(data["error"], "details", "")
													
													if error_type == "overloaded_error"
															put!(channel, "ERROR: Server overloaded. Please try again later.")
													elseif error_type == "api_error"
															put!(channel, "ERROR: Internal server error. Please try again later.")
													else
															put!(channel, "ERROR: $error_msg")
													end
													
													println("\nERROR: $error_msg\n")
													if !isempty(error_details)
															put!(channel, "Details: $error_details")
															println("\nDetails: $error_details\n")
													end
													isdone = true
													break
											else
													println("unknown packet")
													println(line)
											 end
									elseif startswith(line, "event: ") 
											verbose && println(line)
									else
											@show line
											data = JSON.parse(line)
											if data["type"] == "error"
													error_type = get(data["error"], "type", "unknown")
													error_msg = get(data["error"], "message", "Unknown error")
													error_details = get(data["error"], "details", "")
													
													if error_type == "overloaded_error"
															put!(channel, "ERROR: Server overloaded. Please try again later.")
													elseif error_type == "api_error"
															put!(channel, "ERROR: Internal server error. Please try again later.")
													else
															put!(channel, "ERROR: $error_msg")
													end
													
													println("\nERROR: $error_msg\n")
													if !isempty(error_details)
															put!(channel, "Details: $error_details")
															println("\nDetails: $error_details\n")
													end
													isdone = true
													break
											end
									end
									
							end
					end
					HTTP.closeread(io)
			end;
			isopen(channel) && close(channel);
	)

	return channel, user_meta, ai_meta, start_time
end