require 'json'
require 'net/http'

require 'wavefile'
include WaveFile

dd_api_key = ENV["DD_API_KEY"]
dd_app_key = ENV["DD_APP_KEY"]

query = ENV["QUERY"]
if query.nil? || query.empty?
    query = "max:aws.rds.read_iops\{*\}.as_rate()"
end

to = Time.now
from = to - (60 * 60 * 24)

uri = URI("https://api.datadoghq.com/api/v1/query?from=#{from.to_i}&to=#{to.to_i}&query=#{query}")
puts uri

req = Net::HTTP::Get.new(uri)
req["DD-API-KEY"] = dd_api_key
req["DD-APPLICATION-KEY"] = dd_app_key
req["Content-Type"] = "application/json"

res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(req)
end

data = JSON.parse(res.body)
max = 0
min = 0
series = data['series'][0]['pointlist'].collect do |x|
    if x[1] > max 
        max = x[1]
    elsif x[1] < min
        min = x[1]
    end

    x[1]
end

mid = (max + min) / 2

# Window and normalize samples
data = series.to_enum(:each_with_index).collect do |e, i|
    if e > mid
        (e - mid)/ mid
    else
        -1 * (1 - ((e - mid)/mid))
    end
end

Writer.new("sample.wav", Format.new(:mono, :pcm_32, 44100)) do |writer|
    bfmt = Format.new(:mono, :float, 44100)
    buffer = Buffer.new(data, bfmt)
    220.times do 
        writer.write(buffer)
    end
end