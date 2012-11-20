# I've ripped this out of RSpec::Rails so we can run tests that "use_transactional_fixtures" but don't
# require Rails.
#
module TRR

  module SetupAndTeardownAdapter
    extend ActiveSupport::Concern

    module ClassMethods
      # @api private
      #
      # Wraps `setup` calls from within Rails' testing framework in `before`
      # hooks.
      def setup(*methods)
        methods.each do |method|
          if method.to_s =~ /^setup_fixtures$/
            prepend_before { send method }
          else
            before { send method }
          end
        end
      end

      # @api private
      #
      # Wraps `teardown` calls from within Rails' testing framework in
      # `after` hooks.
      def teardown(*methods)
        methods.each { |method| after { send method } }
      end
    end

    # @api private
    def method_name
      @example
    end
  end

  module FixtureSupport
    extend ActiveSupport::Concern
    include SetupAndTeardownAdapter
    include ActiveRecord::TestFixtures

    included do
      # TODO (DC 2011-06-25) this is necessary because fixture_file_upload
      # accesses fixture_path directly on ActiveSupport::TestCase. This is
      # fixed in rails by https://github.com/rails/rails/pull/1861, which
      # should be part of the 3.1 release, at which point we can include
      # these lines for rails < 3.1.
      ActiveSupport::TestCase.class_eval do
        include ActiveRecord::TestFixtures
        self.fixture_path = RSpec.configuration.fixture_path
      end
      # /TODO

      self.fixture_path = RSpec.configuration.fixture_path
      self.use_transactional_fixtures = RSpec.configuration.use_transactional_fixtures
      self.use_instantiated_fixtures = RSpec.configuration.use_instantiated_fixtures
      fixtures RSpec.configuration.global_fixtures if RSpec.configuration.global_fixtures
    end
  end
end

