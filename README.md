## Anthropic.jl

Anthropic.jl is a Julia package that provides a simple interface to interact with Anthropic's AI models, particularly Claude. It extends the functionality of [PromptingTools.jl](https://github.com/svilupp/PromptingTools.jl) to support streaming responses from Anthropic's API.

## Features
- Stream responses from Anthropic's AI models
- Safe API calls with automatic retries for server errors

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/Cvikli/Anthropic.jl.git")
```

## Usage

Here's a quick example of how to use Anthropic.jl:

```julia
using Anthropic

# Set your API key as an environment variable or like this
ENV["ANTHROPIC_API_KEY"] = "your_api_key_here"

# Stream a response
response_channel = ai_stream_safe("Tell me a joke")
response_channel = ai_stream_safe([Dict("role" => "user", "content" => "Tell me a joke")], model="claude-3-opus-20240229", max_tokens=100)


for chunk in response_channel
	print("\e[36m$chunk \e[0m") # Print the streamed response
end

# Or use the non-streaming version which is a wrapper of the ai_generate from promptingtools.
response = ai_ask_safe("What's the capital of France?")
println(response.content)
```

## TODO
Cancel request works on the web...
- Implement response cancellation functionality. Canceling a query should be possible somehow! Do we have "stop" API? example: https://api.claude.ai/api/organizations/d9192fb1-1546-491e-89f2-d3432c9695d2/chat_conversations/f2f779eb-49c5-4605-b8a5-009cdb88fe20/stop_response
- Add support for more Anthropic API features

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
