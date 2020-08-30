require 'tsuga/errors'
require 'tsuga/adapter'
require 'active_record'
require 'delegate'

module Tsuga::Adapter::ActiveRecord
  module Base
    def self.included(by)
      by.extend DatasetMethods
    end

    def id
      @_id ||= super
    end

    def persist!
      save!
    end

    module DatasetMethods
      def mass_create(new_records)
        return if new_records.empty?

        # Old SQLite versions (like on Travis) do not support bulk inserts
        if connection.class.name !~ /sqlite/i || connection.send(:sqlite_version) >= '3.7.11'
          _bulk_insert(new_records)
        else
          new_records.each(&:save!)
        end
      end

      def mass_update(records)
        transaction do
          records.each(&:save!)
        end
      end

      def collect_ids
        pluck(:id)
      end

      private

      def _bulk_insert(records)
        attributes = records.map(&:attributes)
        keys = attributes.first.keys - ['id']
        column_names = keys.map { |k| connection.quote_column_name(k) }.join(', ')
        sql = <<-SQL
          INSERT INTO #{quoted_table_name} (#{column_names}) VALUES
        SQL
        value_template = (['?'] * keys.length).join(', ')
        value_strings = attributes.map do |attrs|
          values = keys.map { |k| attrs[k] }
          sanitize_sql_array([value_template, *values])
        end
        full_sql = sql + value_strings.map { |str| "(#{str})"}.join(', ')
        connection.insert(full_sql)
      end
    end
  end
end
