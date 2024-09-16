
function process_image(image_path)
	image_data = base64encode(read(image_path))
	media_type = lowercase(splitext(image_path)[2]) in [".jpg", ".jpeg"] ? "image/jpeg" : "image/png"
	
	return Dict(
			"type" => "image",
			"source" => Dict(
					"type" => "base64",
					"media_type" => media_type,
					"data" => image_data
			)
	)
end