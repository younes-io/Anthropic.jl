
using Anthropic

res = stream_response("simple story pls")

for r in res
	print("\e[36m$r \e[0m")
end
#%%

#%%

res

