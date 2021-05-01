require 'json'
require 'net/http'

require 'wavefile'
include WaveFile

require 'midilib/sequence'
require 'midilib/consts'
include MIDI

# Note: to_wav is only implemented on a single timeseries metric
#       Could expand this in the future for multiple metrics to multiple wav files!
def to_wav(data)
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
end

# Note: to_midi right now will be implemented with 12-tone temperment qunatization
#       metrics are windows to 2 octave range, centered around middle C
def to_midi(data)
    max = 0
    min = 0
    
    series = data['series'].collect do |p|
        p['pointlist'].collect do |x|
            if x[1] > max 
                max = x[1]
            elsif x[1] < min
                min = x[1]
            end
    
            x[1]
        end
        p
    end

    puts max

    # We have an idea of a min and max, but now we need to be able to find 
    # quantize points between 0-23 (2 octaves of 12 tones)
    diff = max - min
    stride = diff / 24

    # Time to write midi
    seq = Sequence.new()
    track = Track.new(seq)
    seq.tracks << track

    # TODO: Make this configurable
    track.events << Tempo.new(Tempo.bpm_to_mpq(120))
    track.events << MetaEvent.new(META_SEQ_NAME, 'Incident Orchaestra')

    # Window and normalize samples
    data = series.each_with_index do |s, i|
        # Bail if we go over 16 MIDI tracks
        break if i > 15  

        track = Track.new(seq)
        seq.tracks << track
        track.name = s['scope']
        track.instrument = GM_PATCH_NAMES[0]
        track.events << ProgramChange.new(i, 1, 0)
        quarter_note_length = seq.note_to_delta('quarter')

        s['pointlist'].each do |p| 
            # Subtract position from min, divide by stride to get note value
            offset = (p[1] - min) / stride

            # Since we want to center around middle C (midi note 60)
            # apply offset to 12 tones below middle C, (midi note 48)
            midi_note = 48 + offset

            track.events << NoteOn.new(i, 64 + offset, 127, 0)
            track.events << NoteOff.new(i, 64 + offset, 127, quarter_note_length)
        end
    end

    File.open('test.mid', 'wb') { |file| seq.write(file) }
end

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

if ENV['OP'] == "to_midi"
    to_midi(data)
else
    to_wav(data)
end