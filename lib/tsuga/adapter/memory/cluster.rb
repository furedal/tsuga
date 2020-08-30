require 'tsuga/model/cluster'
require 'tsuga/adapter/memory/base'
require 'tsuga/adapter/shared/cluster'

module Tsuga::Adapter::Memory
  module Cluster
    module Fields
      attr_accessor :geohash, :lat, :lng, :depth, :parent_id
      attr_accessor :children_type, :children_ids
      attr_accessor :sum_lat, :sum_lng, :ssq_lat, :ssq_lng, :weight
      attr_accessor :tilecode
    end

    def self.included(by)
      by.send :include, Fields
      by.send :include, Base
      by.send :include, Tsuga::Model::Cluster
      by.send :include, Tsuga::Adapter::Shared::Cluster
      by.extend ClassMethods
    end

    module ClassMethods
      def at_depth(depth)
        scoped(->(r) { r.depth == depth })
      end

      def in_tile(*tiles)
        scoped(->(r) { tiles.any? { |t| (t.depth == r.depth) && t.contains?(r) } })
      end
    end
  end
end
