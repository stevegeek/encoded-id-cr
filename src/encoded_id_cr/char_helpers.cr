module EncodedId
  # Pure-function helpers ported from `ReversibleId`'s private `humanize_length`,
  # `convert_to_hash`, and `map_equivalent_characters` methods. Stateless so they
  # can be composed by the upcoming `ReversibleId` glue without depending on a
  # config object.
  module CharHelpers
    extend self

    # Splits long encoded strings into groups for readability. Inserts
    # `split_with` every `split_at` characters (NOT at the end). Strings shorter
    # than or equal to `split_at` characters are returned unchanged.
    #
    # Example: `humanize_length("abcdefgh", 4, "-") == "abcd-efgh"`
    #
    # Mirrors the Ruby implementation byte-for-byte (separator count = `(len -
    # 1) / split_at`, so a string whose length is an exact multiple of
    # `split_at` does NOT get a trailing separator).
    def humanize_length(s : String, split_at : Int32, split_with : String) : String
      len = s.size
      return s if len <= split_at

      separator_count = (len - 1) // split_at
      # Pre-size the buffer: original chars + (separator_count * separator len)
      result = String.build(len + separator_count * split_with.size) do |io|
        s.each_char_with_index do |ch, idx|
          # Insert the separator BEFORE characters at positions split_at,
          # 2*split_at, ..., separator_count*split_at. This matches Ruby's
          # `String#insert(insert_pos, with)` loop with offsets accumulating.
          if idx > 0 && (idx % split_at) == 0 && (idx // split_at) <= separator_count
            io << split_with
          end
          io << ch
        end
      end
      result
    end

    # Reverses a humanized string for decoding:
    #   1. removes the `split_with` separator (if given)
    #   2. optionally downcases the result
    #   3. applies character equivalences via `tr` (one pair at a time)
    #
    # This collapses Ruby's `convert_to_hash` + `map_equivalent_characters` into
    # a single pure function.
    def unhumanize(s : String, split_with : String?, downcase : Bool, equivalences : Hash(String, String)?) : String
      result = s
      result = result.gsub(split_with, "") if split_with
      result = result.downcase if downcase
      result = map_equivalent_characters(result, equivalences)
      result
    end

    # Applies equivalence mappings to `s` using `String#tr` semantics, one
    # mapping at a time (matches Ruby's `equivalences.reduce(str) { |c, (f,t)|
    # c.tr(f, t) }`). Each key/value is expected to be a single-character
    # String (validated upstream by `Alphabet`).
    def map_equivalent_characters(s : String, equivalences : Hash(String, String)?) : String
      return s if equivalences.nil?
      equivalences.reduce(s) do |cleaned, kv|
        from, to = kv
        cleaned.tr(from, to)
      end
    end
  end
end
