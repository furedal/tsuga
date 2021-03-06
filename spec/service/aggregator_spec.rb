require 'spec_helper'
require 'tsuga/service/aggregator'
require 'tsuga/adapter/memory/cluster'

describe Tsuga::Service::Aggregator do
  let(:adapter) { Class.new { include Tsuga::Adapter::Memory::Cluster } }

  def new_cluster(depth, lat, lng)
    adapter.new.tap do |cluster|
      cluster.depth   = depth
      cluster.lat     = lat
      cluster.lng     = lng
      cluster.weight  = 1
      cluster.sum_lat = lat
      cluster.sum_lng = lng
      cluster.ssq_lat = lat * lat
      cluster.ssq_lng = lng * lng
      cluster.children_ids = []
      cluster.persist!
    end
  end

  subject { described_class.new(clusters:clusters, ratio:0.2) }

  describe '#min_distance' do
    let(:clusters) { [new_cluster(2,0,0)] }

    it 'is about 20% of a tile diagonal' do
      subject.min_distance.should == be_within(1e-6).of(Math.sqrt(45*45 + 90*90) / 5)
    end
  end

  describe '#run' do
    context 'when the list of clusters is empty' do
      let(:clusters) { [] }
      it('passes') { subject.run }
    end

    context 'with a single cluster' do
      let(:clusters) { [new_cluster(2,0,0)] }
      it('passes') { subject.run }
    end

    context 'with 4 distant clusters' do
      let(:north) { 0 }
      let(:south) { 45 - 1e-4 }
      let(:west)  { 0 }
      let(:east)  { 90 - 1e-4 }

      let(:clusters) {[
        new_cluster(2, north, west),
        new_cluster(2, south, west),
        new_cluster(2, south, east),
        new_cluster(2, north, east)
      ]}
      
      it('passes') { subject.run }

      it('preserves clusers') do 
        subject.run
        clusters.length.should == 4
      end
    end


    context 'with 3 close clusters' do
      let(:lat) { 22.5 }
      let(:lng) { 45 }

      let(:clusters) {[
        new_cluster(2, lat + 0, lng),
        new_cluster(2, lat + 1, lng),
        new_cluster(2, lat - 1, lng)
      ]}
      
      it('passes') { subject.run }

      it 'groups clusters' do 
        subject.run
        clusters.length.should == 1
      end

      it 'computes centroid' do
        subject.run
        clusters.first.tap do |cluster|
          cluster.lat.should == lat
          cluster.lng.should == lng
        end
      end
    end


    context 'with superimposed points' do
      let(:lat) { 22.5 }
      let(:lng) { 45 }

      let(:clusters) {[
        new_cluster(2, lat, lng),
        new_cluster(2, lat, lng),
        new_cluster(2, lat, lng)
      ]}
      
      it('passes') { subject.run }

      it 'groups clusters' do 
        subject.run
        clusters.length.should == 1
      end
    end

    context 'with 2 close and 2 distant clusters' do
      let(:lat) { 22.5 }
      let(:lng) { 45 }

      let(:clusters) {[
        new_cluster(2, 22, 45),
        new_cluster(2, 23, 46),
        new_cluster(2,  0,  0),
        new_cluster(2,  1,  1)
      ]}
      
      it('passes') { subject.run }

      it 'groups clusters' do 
        subject.run
        clusters.length.should == 2
      end
    end

    context 'with 100 random clusters' do
      let(:lat_max) { 45 - 1e-4 }
      let(:lng_max) { 90 - 1e-4 }

      let(:clusters) { 
        (1...100).map { new_cluster(2, rand*lat_max, rand*lng_max) }
      }
      
      it('passes') { subject.run }
    end

  end

end