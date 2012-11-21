require 'rubygems'
require 'active_record'
require 'factory_girl'
require File.expand_path('../../support/active_record_support', __FILE__)
require File.expand_path('../../support/test_entities', __FILE__)

FactoryGirl.find_definitions

RSpec.configure do |c|
  c.include Seize::FixtureSupport
  c.add_setting :use_transactional_fixtures, :alias_with => :use_transactional_examples
  c.add_setting :use_instantiated_fixtures
  c.add_setting :global_fixtures
  c.add_setting :fixture_path
end
