require 'tsuga/model/cluster'
require 'tsuga/model/tile'
require 'tsuga/adapter/active_record/base'
require 'tsuga/adapter/shared/cluster'

module Tsuga::Adapter::ActiveRecord
  module Cluster

    def self.included(by)
      by.send :include, Base
      by.send :include, Tsuga::Model::Cluster
      by.send :include, Tsuga::Adapter::Shared::Cluster
      by.extend Scopes

      by.class_eval do
        belongs_to :parent, optional: true, class_name: by.name
      end
    end

    def parsed_cluster(zoom)
      return {
        id:           self.id,
        weight:       self.weight,
        lat:          self.lat,
        lng:          self.lng,
        zoom:         zoom,
        children_ids: self.children_ids.join(',')
      }
    end

    def children_ids
      @_children_ids ||= begin
        stored = super
        stored ? stored.split(',').map(&:to_i) : []
      end
    end

    def children_ids=(value)
      changed = (@_children_ids != value)
      @_children_ids = value
      super(@_children_ids.join(',')) if changed
      @_children_ids
    end

    def children_clusters
      return [] unless self.children.present?
  
      # A cluster at depth N may not break into sub-clusters at depth N+1 but
      # rather at some greater depth.  This loop drills down until the cluster
      # breaks up.
      children = self.get_children_at_depth_where_more_than_one
      zoom = children.first.depth
      return self.class.parsed_clusters(children, zoom), zoom
    end

    def delete_monoclusters
      cluster = self
      while cluster.present? && cluster.monocluster?
        parent_cluster = cluster.parent
        id_of_last_deleted_cluster = cluster.id
        cluster.delete
        cluster = parent_cluster
      end
      return id_of_last_deleted_cluster, cluster
    end
  
    def adjust_cluster_weights_from_here_to_root(delta_weight)
      cluster = self
      while cluster.present?
        new_weight = clamp(cluster.weight + delta_weight, 0, nil)
        cluster.update!(weight: new_weight)
        cluster = cluster.parent
      end
    end
  
    def remove_child_cluster(id)
      children_ids = self.children_ids
      pruned_ids = children_ids.reject { |e| e == id }
      self.children_ids = pruned_ids
      self.save!
    end
  
    def get_zoom_for_children
      return nil unless self.children.present?
      children = self.get_children_at_depth_where_more_than_one
  
      # The expected zoom value is the zoom level at which it would be suitable to show these children
      # clusters in Google Maps.  Tsuga was designed so that the depth of the cluster in the cluster hierarchy
      # maps onto these zoom levels, which is why here we can just return the depth of any of the children
      # (clamped to within the allowed range).
      clamp(children.first.depth, Tsuga::MIN_DEPTH, Tsuga::MAX_DEPTH)
    end
  
    def get_children_at_depth_where_more_than_one
      # A cluster at depth N may not break into sub-clusters at depth N+1 but
      # rather at some greater depth.  This loop drills down until the cluster
      # breaks up. This will only happen if the cluster has a weight greater
      # than one.
      children = self.children
      while children.size == 1 && children.first.weight > 1 && children.first.depth < Tsuga::MAX_DEPTH do
        parent = children.first
        children = parent.children
      end
      return children
    end

    module Scopes

      def at_depth(depth)
        where(depth: depth)
      end

      # FIXME: this also is redundant with the mongoid adapter implementation
      def in_tile(*tiles)
        depths = tiles.map(&:depth).uniq
        raise ArgumentError, 'all tile must be at same depth' if depths.length > 1
        where(tilecode: tiles.map(&:prefix))
      end

      def in_viewport(sw:nil, ne:nil, depth:nil)
        tiles = Tsuga::Model::Tile.enclosing_viewport(point_sw: sw, point_ne: ne, depth: depth)
        in_tile(*tiles)
      end
    end
  end
end
