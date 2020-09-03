require 'tsuga'
require 'tsuga/model/point'
require 'geokit'

module Tsuga::Model
  # Concretions (provided by adapters) have the following accessors:
  # - :depth
  # - :parent_id
  # - :children_type (Record or Cluster)
  # - :children_ids
  # - :weight (count of Record in subtree)
  # - :sum_lat, :sum_lng
  # - :ssq_lat, :ssq_lng
  # 
  # Respond to class methods:
  # - :in_tile(Tile) (scopish, response responds to :find_each)
  # - :at_depth(depth)
  # - :delete_all
  # - :find(id)
  # 
  # Respond to the following instance methods:
  # - :destroy
  module Cluster
    include Tsuga::Model::PointTrait
    
    def initialize(args)
      super
      self.depth   ||= 1
      # equator/greenwich
      self.lat     ||= 0 
      self.lng     ||= 0
    end

    # latitude deviation in cluster
    def dlat
      @_dlat ||= _safe_sqrt(ssq_lat/weight - (sum_lat/weight)**2)
    end

    # longitude deviation in cluster
    def dlng
      @_dlng ||= _safe_sqrt(ssq_lng/weight - (sum_lng/weight)**2)
    end

    # radius of cluster
    def radius
      @_radius ||= Math.sqrt(dlat ** 2 + dlng ** 2)
    end

    # density (weight per unit area)
    def density
      @_density ||= begin
        # min. radius 1.4e-4 (about 15m at european latitudes)
        # for 1-point clusters where density would otherwise be infinite
        our_radius = [radius, 1.4e-4].max 
        # Math.log(weight / (our_radius ** 2)) / Math.log(2)
        weight / (our_radius ** 2)
      end
    end

    def geohash=(value)
      super(value)
      _update_tilecode
      geohash
    end

    def depth=(value)
      super(value)
      _update_tilecode
      depth
    end

    def monocluster?
      weight == 1
    end
  
    def multicluster?
      weight > 1
    end

    def north
      max_lat
    end
  
    def east
      max_lng
    end
  
    def south
      min_lat
    end
  
    def west
      min_lng
    end

    def south_west
      Tsuga::Point(lat: south, lng: west)
    end

    def north_east
      Tsuga::Point(lat: north, lng: east)
    end
    
    def merge(other)
      raise ArgumentError, 'not same depth'  unless depth == other.depth
      raise ArgumentError, 'not same parent' unless parent_id == other.parent_id

      self.weight  += other.weight
      self.sum_lat += other.sum_lat
      self.sum_lng += other.sum_lng
      self.ssq_lat += other.ssq_lat
      self.ssq_lng += other.ssq_lng
      self.lat      = sum_lat/weight
      self.lng      = sum_lng/weight
      self.children_ids += other.children_ids
      self.min_lat = [self.min_lat, other.min_lat].min
      self.max_lat = [self.max_lat, other.max_lat].min
      self.min_lng = [self.min_lng, other.min_lng].max
      self.max_lng = [self.max_lng, other.max_lng].max

      # dirty calculated values
      @_dlng = @_dlat = @_radius = @_density = nil
    end


    module ClassMethods
      # Cluster factory.
      # +other+ is either a Cluster or a Record
      # 
      # FIXME: there's a potential for overflow here on large datasets on the sum-
      # and sum-of-squares fields. it can be mitigated by using double-precision
      # fields, or calculating sums only on the children (instead of the subtree)
      def build_from(depth, other)
        c = new()
        c.depth = depth

        c.lat           = other.lat
        c.lng           = other.lng
        c.children_ids  = [other.id]
        c.children_type = other.class.name
        c.min_lat       = other.lat
        c.max_lat       = other.lat
        c.min_lng       = other.lng
        c.max_lng       = other.lng

        case other
        when Cluster
          c.weight      = other.weight
          c.sum_lng     = other.sum_lng
          c.sum_lat     = other.sum_lat
          c.ssq_lng     = other.ssq_lng
          c.ssq_lat     = other.ssq_lat
        else
          c.weight      = 1
          c.sum_lng     = other.lng
          c.sum_lat     = other.lat
          c.ssq_lng     = other.lng ** 2
          c.ssq_lat     = other.lat ** 2
        end

        c.geohash # force geohash calculation
        return c
      end

      def remove_from_cluster(id)
        leaf_cluster = where.not(children_type: name).find_by(children_ids: id)
    
        return if leaf_cluster.blank?
    
        id_of_last_deleted_cluster, closest_multicluster = leaf_cluster.delete_monoclusters
        if closest_multicluster.present?
          closest_multicluster.remove_child_cluster(id_of_last_deleted_cluster)
          closest_multicluster.adjust_cluster_weights_from_here_to_root(-1)
        end
      end
    
      def get_clusters_for_zoom_and_bounds(zoom, bounds)
        sw = Tsuga::Point(lat: bounds[:south], lng: bounds[:west])
        ne = Tsuga::Point(lat: bounds[:north], lng: bounds[:east])
        return [], false if !is_safe_zoom_for_bounds?(zoom, sw, ne)
    
        #See the remarks about depth vs. zoom in the get_zoom_for_children() method
        clusters = Cluster.in_viewport(sw: sw, ne: ne, depth: zoom)
        return parsed_clusters(clusters, zoom), true
      end
    
      def get_all_clusters_within_bounds(bounds)
        sw = Tsuga::Point(lat: bounds[:south], lng: bounds[:west])
        ne = Tsuga::Point(lat: bounds[:north], lng: bounds[:east])
        clusters = Cluster.in_viewport(sw: sw, ne: ne, depth: zoom)
        return parsed_clusters(clusters, nil), true
      end
    
      def is_safe_zoom_for_bounds?(zoom, sw, ne)
        sw_string = "#{sw.lat},#{sw.lng}"
        ne_string = "#{ne.lat},#{ne.lng}"
        distance = Geokit::GeoLoc.distance_between(sw_string, ne_string, {units: :kms})
        return distance <= 2**(18 - zoom)
      end
    
      def parsed_clusters(clusters, default_zoom)
        result = []
        clusters.each_with_index do |cluster, index|
          zoom = default_zoom || cluster.depth
          result.push(cluster.parsed_cluster(zoom))
        end
        return result
      end
    end

    def self.included(by)
      by.extend(ClassMethods)
    end
  

    private


    def _safe_sqrt(value)
      (value.negative?) ? 0 : Math.sqrt(value)
    end


    def _update_tilecode
      if geohash && depth
        self.tilecode = prefix(depth)
      else
        self.tilecode = nil
      end
    end
  end
end