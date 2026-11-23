require "./spec_helper"
require "json"

# Golden hex IDs from the Ruby gem's test/fixtures/hex_ids.json: IDs issued by
# release 1.1.1 and by the current legacy encoding, for both encoders.
HEX_FIXTURES    = JSON.parse(File.read(File.join(__DIR__, "fixtures", "hex_ids.json")))
HEX_GROUP_SIZES = [1, 4, 8, 12]

private def hex_coder(fixture : JSON::Any, hex_encoding : EncodedId::HexEncoding) : EncodedId::ReversibleId
  group_size = fixture["group_size"].as_i
  if fixture["encoder"].as_s == "sqids"
    EncodedId::ReversibleId.sqids(
      blocklist: EncodedId::Blocklist.empty,
      hex_digit_encoding_group_size: group_size,
      hex_encoding: hex_encoding,
      max_length: nil,
    )
  else
    EncodedId::ReversibleId.hashid(
      salt: HEX_FIXTURES["salt"].as_s,
      hex_digit_encoding_group_size: group_size,
      hex_encoding: hex_encoding,
      max_length: nil,
    )
  end
end

private def fixture_hexes(fixture : JSON::Any) : Array(String)
  input = fixture["input"]
  hexes = input.as_a? ? input.as_a.map(&.as_s) : [input.as_s]
  hexes.map(&.delete('-'))
end

describe "hex encoding compatibility with the Ruby gem" do
  it "decodes IDs issued by release 1.1.1 as they did then" do
    HEX_FIXTURES["release_1_1_1"].as_a.each do |fixture|
      decoded = fixture["decoded"].as_a.map(&.as_s)
      id = fixture["id"].as_s
      hex_coder(fixture, EncodedId::HexEncoding::Legacy).decode_hex(id).should eq(decoded)
      hex_coder(fixture, EncodedId::HexEncoding::Tagged).decode_hex(id, scheme: EncodedId::HexEncoding::Legacy).should eq(decoded)
    end
  end

  it "matches the legacy encoding fixtures and round-trips them" do
    HEX_FIXTURES["current"].as_a.each do |fixture|
      coder = hex_coder(fixture, EncodedId::HexEncoding::Legacy)
      hexes = fixture_hexes(fixture)
      coder.encode_hex(hexes).should eq(fixture["id"].as_s) unless hexes.any?(&.empty?)
      coder.decode_hex(fixture["id"].as_s).should eq(hexes)
    end
  end

  it "round-trips the fixture inputs with the tagged encoding" do
    (HEX_FIXTURES["release_1_1_1"].as_a + HEX_FIXTURES["current"].as_a).each do |fixture|
      hexes = fixture_hexes(fixture)
      next if hexes.any?(&.empty?)
      coder = hex_coder(fixture, EncodedId::HexEncoding::Tagged)
      coder.decode_hex(coder.encode_hex(hexes)).should eq(hexes)
    end
  end

  it "covers both encoders and every group size" do
    %w[release_1_1_1 current].each do |set|
      covered = HEX_FIXTURES[set].as_a.map { |fixture| {fixture["encoder"].as_s, fixture["group_size"].as_i} }.uniq!.sort!
      covered.should eq(%w[hashid sqids].flat_map { |encoder| HEX_GROUP_SIZES.map { |size| {encoder, size} } })
    end
  end

  it "only decodes legacy hex IDs that are canonical" do
    random = Random.new(42)
    decoded_count = 0
    %w[sqids hashid].each do |encoder|
      HEX_GROUP_SIZES.each do |group_size|
        coder = hex_coder(JSON.parse({encoder: encoder, group_size: group_size}.to_json), EncodedId::HexEncoding::Legacy)
        legacy = EncodedId::HexRepresentation.new(group_size)
        separator = 16_i64 ** group_size
        300.times do
          integers = Array(Int64).new(random.rand(1..5)) do
            case random.rand(4)
            when 0 then random.rand(separator)
            when 1 then random.rand(16_i64)
            when 2 then separator
            else        separator + 1 + random.rand(group_size + 2)
            end
          end
          id = coder.encode(integers)
          decoded = coder.decode_hex(id)
          next if decoded.empty? || decoded.any?(&.empty?)

          decoded_count += 1
          # The second ID is the 1.1.1 encoding of an empty first string followed by the decoded strings.
          [coder.encode_hex(decoded), coder.encode([separator] + legacy.hex_as_integers(decoded))].should contain(id)
        end
      end
    end
    decoded_count.should be > 400
  end

  it "only decodes tagged hex IDs that are canonical" do
    random = Random.new(42)
    decoded_count = 0
    %w[sqids hashid].each do |encoder|
      coder = hex_coder(JSON.parse({encoder: encoder, group_size: 4}.to_json), EncodedId::HexEncoding::Tagged)
      1000.times do
        integers = Array(Int64).new(random.rand(1..5)) do
          tag = random.rand(4).zero? ? random.rand(4).to_s : %w[1 2].sample(random)
          length = random.rand(3).zero? ? random.rand(16) : [15, 14, 0].sample(random)
          (tag + String.build { |io| length.times { io << random.rand(16).to_s(16) } }).to_i64(16)
        end
        id = coder.encode(integers)
        decoded = coder.decode_hex(id)
        next if decoded.empty? || decoded.any?(&.empty?)

        decoded_count += 1
        coder.encode_hex(decoded).should eq(id)
      end
    end
    decoded_count.should be > 100
  end
end
