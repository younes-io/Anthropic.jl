
@kwdef mutable struct StreamMeta
    id::String=""
    input_tokens::Int=0
    output_tokens::Int=0
    price::Float32=0f0
    elapsed::Float64=0f0
end
to_dict(x::StreamMeta) = Dict((name => getproperty(x, name) for name in propertynames(x)))


const TOKEN_COSTS = Dict(
    "claude-3-opus-20240229" => (input = 15 / 1000000, output = 75 / 1000000),
    "claude-3-5-sonnet-20240620" => (input = 3 / 1000000, output = 15 / 1000000),
    "claude-3-sonnet-20240229" => (input = 3 / 1000000, output = 15 / 1000000),
    "claude-3-haiku-20240307" => (input = 0.25 / 1000000, output = 1.25 / 1000000),
    "claude-2.1" => (input = 8 / 1000000, output = 24 / 1000000),
    "claude-2.0" => (input = 8 / 1000000, output = 24 / 1000000),
    "claude-instant-1.2" => (input = 0.8 / 1000000, output = 2.4 / 1000000)
)

function call_cost(input_tokens::Int, output_tokens::Int, model::String)
    if !haskey(TOKEN_COSTS, model)
        @warn "Model $model not found in TOKEN_COSTS. Using default costs."
        return 0.0
    end
    
    costs = TOKEN_COSTS[model]
    input_cost = input_tokens * costs.input
    output_cost = output_tokens * costs.output
    
    return input_cost + output_cost
end
call_cost!(meta::StreamMeta, model::String) = (meta.price = call_cost(meta.input_token, meta.output_token, model))

initStreamMeta(id::String, in_tok::Int, out_tok::Int, model::String) = call_cost!(StreamMeta(id, in_tok, out_tok, 0f0), model)
