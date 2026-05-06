require "option_parser"
require "./encoded_id_cr"

# Tiny CLI for encoded_id_cr. Default encoder is Sqids (no salt needed); pass
# --salt SALT to switch to Hashids. Examples:
#
#   cr_encoded_id encode 12345
#   cr_encoded_id encode 12345 --salt foo
#   cr_encoded_id encode 1 2 3 --salt foo --min-length 8
#   cr_encoded_id decode 37vq-3u7t
#   cr_encoded_id decode m3pm-8anj --salt foo
class CrEncodedIdCli
  enum Mode
    Encode
    Decode
  end

  property mode : Mode?
  property salt : String?
  property encoder : String?
  property alphabet_name : String = "modified_crockford"
  property min_length : Int32 = 8
  property no_humanize : Bool = false
  property values : Array(String) = [] of String

  def parse(argv : Array(String))
    OptionParser.parse(argv) do |parser|
      parser.banner = "Usage: cr_encoded_id <encode|decode> [values...] [options]"

      parser.unknown_args do |unknown, _after_dash|
        if first = unknown.shift?
          case first
          when "encode" then @mode = Mode::Encode
          when "decode" then @mode = Mode::Decode
          else
            STDERR.puts "Unknown command: #{first}. Expected 'encode' or 'decode'."
            exit 2
          end
        end
        @values = unknown
      end

      parser.on("--salt=SALT", "Use Hashids with this salt (otherwise Sqids)") { |v| @salt = v }
      parser.on("--encoder=NAME", "Force encoder: 'sqids' or 'hashid'") { |v| @encoder = v }
      parser.on("--alphabet=NAME", "Alphabet: 'modified_crockford' (default) or 'alphanum'") do |v|
        @alphabet_name = v
      end
      parser.on("--min-length=N", "Minimum encoded length (default 8)") { |v| @min_length = v.to_i }
      parser.on("--no-humanize", "Disable separator insertion") { @no_humanize = true }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end
  end

  def run
    case @mode
    when Mode::Encode then encode
    when Mode::Decode then decode
    else
      STDERR.puts "Missing command. Use 'encode' or 'decode'. Try --help."
      exit 2
    end
  end

  private def alphabet : EncodedId::Alphabet
    case @alphabet_name
    when "modified_crockford" then EncodedId::Alphabet.modified_crockford
    when "alphanum"           then EncodedId::Alphabet.alphanum
    else
      STDERR.puts "Unknown alphabet: #{@alphabet_name}"
      exit 2
    end
  end

  private def reversible_id : EncodedId::ReversibleId
    use_hashid = (@encoder == "hashid") || (@encoder.nil? && !@salt.nil?)
    split_at = @no_humanize ? nil : 4

    if use_hashid
      EncodedId::ReversibleId.hashid(
        salt: @salt || "",
        alphabet: alphabet,
        min_hash_length: @min_length,
        split_at: split_at,
      )
    else
      EncodedId::ReversibleId.sqids(
        alphabet: alphabet,
        min_length: @min_length,
        split_at: split_at,
      )
    end
  end

  private def encode
    if @values.empty?
      STDERR.puts "encode requires one or more numeric arguments"
      exit 2
    end
    nums = @values.map do |v|
      v.to_i64? || (STDERR.puts("Not an integer: #{v}"); exit 2)
    end
    puts reversible_id.encode(nums)
  rescue err : EncodedId::Error
    STDERR.puts "Error: #{err.message}"
    exit 1
  end

  private def decode
    if @values.size != 1
      STDERR.puts "decode requires exactly one encoded string"
      exit 2
    end
    result = reversible_id.decode(@values[0])
    puts result.join(" ")
  rescue err : EncodedId::Error
    STDERR.puts "Error: #{err.message}"
    exit 1
  end
end

cli = CrEncodedIdCli.new
cli.parse(ARGV.dup)
cli.run
