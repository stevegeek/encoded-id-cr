require "benchmark"
require "../src/encoded_id_cr"

# Apples-to-apples benchmark of the encoded_id_cr Crystal port vs the Ruby
# `encoded_id` gem's optimised internal encoders. Both sides exercise:
#
#   - Sqids: Crystal `EncodedId::Encoders::Sqids` (ported MySqids)
#            vs Ruby top-level `MySqids` class (the optimised internal one,
#            same source we ported)
#   - Hashid: Crystal `EncodedId::Encoders::Hashid` vs Ruby
#             `EncodedId::Encoders::Hashid`
#
# Output uses Benchmark.ips so iterations/sec is directly comparable to
# Ruby's benchmark-ips output.

ALPHA      = EncodedId::Alphabet.modified_crockford
SALT_STR   = "this is my salt"
SALT       = EncodedId::Encoders::HashidSalt.new(SALT_STR)
SQIDS_OP   = EncodedId::Encoders::Sqids.new(8, ALPHA.characters, [] of String)
HASHID_OP  = EncodedId::Encoders::Hashid.new(SALT, 0, ALPHA)

SINGLE_ID  = [12345_i64]
FIVE_IDS   = [1_i64, 2_i64, 3_i64, 4_i64, 5_i64]
SQIDS_ENC1 = SQIDS_OP.encode(SINGLE_ID)
SQIDS_ENC5 = SQIDS_OP.encode(FIVE_IDS)
HASHID_ENC1 = HASHID_OP.encode(SINGLE_ID)
HASHID_ENC5 = HASHID_OP.encode(FIVE_IDS)

puts "Crystal encoded_id_cr benchmark"
puts "Crystal #{Crystal::VERSION} on #{`uname -m`.strip}"
puts

Benchmark.ips do |x|
  x.report("sqids encode 1 id   ") { SQIDS_OP.encode(SINGLE_ID) }
  x.report("sqids encode 5 ids  ") { SQIDS_OP.encode(FIVE_IDS) }
  x.report("sqids decode 1 id   ") { SQIDS_OP.decode(SQIDS_ENC1) }
  x.report("sqids decode 5 ids  ") { SQIDS_OP.decode(SQIDS_ENC5) }
  x.report("hashid encode 1 id  ") { HASHID_OP.encode(SINGLE_ID) }
  x.report("hashid encode 5 ids ") { HASHID_OP.encode(FIVE_IDS) }
  x.report("hashid decode 1 id  ") { HASHID_OP.decode(HASHID_ENC1) }
  x.report("hashid decode 5 ids ") { HASHID_OP.decode(HASHID_ENC5) }
end
