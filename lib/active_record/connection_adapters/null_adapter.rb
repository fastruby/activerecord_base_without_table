# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    # This class is a concrete implementation of ConnectionAdapters::AbstractAdapter
    # that eliminates all code paths attempting to open a connection to a real
    # database backend.
    class NullAdapter < SimpleDelegator
      def schema_cache
        NullSchemaCache.new
      end
    end
  end
end
