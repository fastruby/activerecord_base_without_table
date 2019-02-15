# frozen_string_literal: true

require 'active_record/attributes_builder_without_table'
require 'active_record/connection_adapters/null_adapter'
require 'active_record/connection_adapters/null_schema_cache'

module ActiveRecord
  # Get the power of ActiveRecord models, including validation, without having a
  # table in the database.
  #
  # == Usage
  #
  #   class Contact < ActiveRecord::BaseWithoutTable
  #     column :name, :text
  #     column :email_address, :text
  #     column :message, :text
  #   end
  #
  #   validates_presence_of :name, :email_address, :string
  #
  # This model can be used just like a regular model based on a table, except it
  # will never be saved to the database.
  #
  class BaseWithoutTable
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveRecord::AttributeMethods::BeforeTypeCast
    include ActiveModel::Validations
    include ActiveModel::Validations::Callbacks
    extend ActiveModel::Validations::HelperMethods
    extend ActiveModel::Callbacks
    extend ActiveRecord::Sanitization::ClassMethods

    class_attribute :associations_to_eager_load 

    define_model_callbacks :initialize

    class << self
      def attribute_names
        _default_attributes.keys.map(&:to_s)
      end

      def column(name, sql_type = nil, default = nil, null = true)
        attribute name, lookup_attribute_type(sql_type), default: default, null: null
      end

      def lookup_attribute_type(sql_type)
        # This is an emulation of the Rails 4.1 runtime behaviour.
        # Please consider rewriting once we move to Rails 5.1.
        mapped_sql_type =
          case sql_type
          when :datetime
            :date_time
          when :datetime_point
            :integer
          when :enumerable
            :value
          else
            sql_type
          end.to_s.camelize

          if mapped_sql_type == "DateTime"
            ::ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(::ActiveRecord::Type::DateTime.new)
          else
            "::ActiveRecord::Type::#{mapped_sql_type}".constantize.new
          end
      end

      def gettext_translation_for_attribute_name(attribute)
        # `rake gettext:store_model_attributes` processes our BaseWithoutTable models, but we have our own rake task
        # for that. Return right away if calling gettext_translation_for_attribute_name on BaseWithoutTable
        return "BaseWithoutTable" if self == BaseWithoutTable

        attribute = attribute.to_s
        if attribute.ends_with?("_id")
          humanize_class_name(attribute)
        else
          "#{self}|#{attribute.split('.').map!(&:humanize).join('|')}"
        end
      end

      def find_by_sql(sql_query, binds = [])
        execute_query(sql_query, binds).map(&method(:new))
      end

      def belongs_to(association_name, options = {})
        self.associations_to_eager_load ||= []
        self.associations_to_eager_load += [[association_name, options]]
        attribute association_name
      end

      def init_belongs_to(results, association, foreign_key: "#{association}_id", class_name: association.to_s)
        associated_class = case class_name
                           when String
                             class_name.classify.constantize
                           when Class
                             class_name
                           else
                             raise "Invalid class #{class_name.inspect}"
                           end

        association_ids = results.map { |result| result.send(foreign_key) }.compact
        associated_objects_by_id = associated_class.find(association_ids).index_by(&:id)

        results.each do |result|
          association_id = result.send(foreign_key)
          result.send("#{association}=", associated_objects_by_id[association_id])
        end
      end

      def execute_query(sql_query, binds)
        ::ActiveRecord::Base.connection.select_all(
          sanitize_sql(sql_query),
          "#{self.class.name} Load",
          binds
        )
      end
    end

    def initialize(*args)
      run_callbacks :initialize do
        super

        if self.class.associations_to_eager_load
          self.class.associations_to_eager_load.each do |association_name, options = {}|
            self.class.init_belongs_to([self], association_name, options)
          end
        end
      end
    end
  end
end
