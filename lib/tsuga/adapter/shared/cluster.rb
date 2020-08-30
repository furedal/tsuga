require 'tsuga/adapter/shared'

# Shared functionality between adapters
module Tsuga::Adapter::Shared::Cluster
  def children
    return [] if children_ids.nil?
    self.class.where(id: children_ids)
  end

  def leaves
    if children_type != self.class.name || children_ids.blank?
      [self]
    else
      children.map(&:leaves).inject(:+)
    end
  end
end