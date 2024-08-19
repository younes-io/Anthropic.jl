
using Anthropic

res = stream_response("simple story pls")
#%%
for r in res
	print("\e[36m$r \e[0m")
end
#%%

using Anthropic: channel_to_string
tes = channel_to_string(stream_response("simple story pls"))
#%%

res

#%%


mutable struct StreamMeta
	id::String
	input_token::Int
	output_token::Int
	price::Float32
end


to_dict(x::StreamMeta) = Dict((name => getproperty(x, name) for name in propertynames(x)))
meta = StreamMeta("",0,0, 0f0)

to_dict(meta)
