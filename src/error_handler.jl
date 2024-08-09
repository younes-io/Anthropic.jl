using PromptingTools
using PromptingTools: SystemMessage, UserMessage, AIMessage

function safe_fn(func, args...; max_retries=3, kwargs...)
    for attempt in 1:max_retries
        try
            return func(args...; kwargs...)
        catch e
            if e isa HTTP.StatusError && e.status in [500, 529]
                if attempt < max_retries
                    sleep_time = 2^attempt
                    @warn "Server error (status $(e.status)). Retrying in $sleep_time seconds... (Attempt $attempt of $max_retries)"
                    sleep(sleep_time)
                else
                    @error "Failed after $max_retries attempts due to persistent server errors."
                    errmsg = IOBuffer()
                    Base.showerror(errmsg, e, Base.catch_backtrace())
                    return AIMessage(String(take!(errmsg)))
                end
            else
                @error "Unhandled error occurred: $(e)"
                rethrow(e)
            end
        end
    end
    error("Unexpected exit from retry loop")
end
