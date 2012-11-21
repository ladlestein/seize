module Seize

  class Designer < ActiveRecord::Base
    attr_accessible :name, :code, :chicness
    validates_length_of :code, :maximum => 3
    validates :name, :presence => true
  end

  class Product < ActiveRecord::Base
    has_and_belongs_to_many :categories, :join_table => 'products_categories'
    has_many :variants
    belongs_to :designer
  end

  class Variant < ActiveRecord::Base
    belongs_to :product
    belongs_to :user
  end

  class Category < ActiveRecord::Base
    attr_accessible :name
  end

  class User < ActiveRecord::Base
    has_many :variants
  end

end
