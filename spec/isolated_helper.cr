# Isolated spec helper for the alphabet/char_helpers work. Mirrors the error
# class definitions from `src/encoded_id_cr.cr` so these specs can run without
# loading the full entry point (which requires `encoders/sqids.cr` from the
# parallel agent's WIP and won't compile until that lands).
require "spec"

module EncodedId
  class Error < Exception; end

  class InvalidAlphabetError < Error; end

  class InvalidConfigurationError < Error; end

  class InvalidInputError < Error; end

  class EncodedIdFormatError < Error; end

  class EncodedIdLengthError < Error; end
end

require "../src/encoded_id_cr/alphabet"
require "../src/encoded_id_cr/char_helpers"
