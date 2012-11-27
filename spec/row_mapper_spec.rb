require 'support/spec_helper'
require 'tempfile'
require File.expand_path('../../lib/seize/row_mapper', __FILE__)
require File.expand_path('../support/test_entities', __FILE__)

include Seize

describe "the row mapper" do

  self.use_transactional_fixtures = true

  before :all do
    @db_file = Tempfile.new("development.sqlite3")

    ActiveRecord::Base.configurations[:development] = {}
    ActiveRecord::Base.establish_connection :adapter => 'sqlite3', :database => @db_file.path
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table :designers do |t|
        t.string :name
        t.string :code
        t.string :chicness
      end

      create_table :products do |t|
        t.string   :name,                 :default => "",    :null => false
        t.integer  :designer_id
      end

      create_table :categories do |t|
        t.string   :name
      end

      create_table :products_categories, :id => false, :force => true do |t|
        t.integer :product_id
        t.integer :category_id
      end

      create_table :variants do |t|
        t.string   :sku
        t.integer  :product_id
        t.integer  :user_id
      end

      create_table :users do |t|
        t.string   :name
      end
    end
  end

  after :all do
    @db_file.delete
  end


  def variant(product)
    product.variants.should_not be_nil
    product.variants.length.should eq(1)
    product.variants[0]
  end

  context "basic mapping" do

    let(:mapper) { RowMapper.new(Designer) }

    it "creates an instance of the right class" do
      result = mapper.map([])

      result.should be_an_instance_of(Designer)
    end

    it "maps a cell in a row" do

      mapper.field :name

      result = mapper.map %w(Cletus)

      result.should be_an_instance_of(Designer)
      result.name.should eq("Cletus")
    end

    it "maps cells in order" do

      mapper.field :code
      mapper.field :name

      result = mapper.map %w(CLE Cletus)

      result.code.should eq("CLE")
      result.name.should eq("Cletus")
    end

    it "ignores cells when told to" do
      mapper.field :code
      mapper.ignored
      mapper.field :name

      result = mapper.map %w(CLE kaddidle Cletus)

      result.name.should eq("Cletus")
    end

    it "handles headers in the data row" do
      mapper.field :name

      result = mapper.map [%w(something Cletus)]

      result.name.should eq("Cletus")
    end

    it "handles multiple fields for a single cell" do
      mapper.cell {
        field :name
        field :code
      }

      result = mapper.map %w(pizza)

      result.name.should eq("pizza")
      result.code.should eq("pizza")
    end

    it "uses a value resolver" do
      name = "something or other"
      new_name = "Mr. Happy"
      mapper.field :name, resolve_with: (lambda do |value|
        value.should eq(name)
        new_name
      end)

      result = mapper.map [name]

      result.name.should eq(new_name)
    end

    it "honors dependencies" do
      ordermaster = double

      grandparent_resolver = lambda do |value, root|
        value.should eq("chicness")
        ordermaster.grandparent
      end

      child_resolver = lambda do |value, root|
        value.should eq("name")
        ordermaster.child
        ""
      end

      parent_resolver = lambda do |value, root|
        value.should eq("code")
        ordermaster.parent
        ""
      end

      mapper.field :code, resolve_with: parent_resolver, depends_on: :chicness
      mapper.field :name, resolve_with: child_resolver, depends_on: :code
      mapper.field :chicness, resolve_with: grandparent_resolver

      ordermaster.should_receive(:grandparent).ordered
      ordermaster.should_receive(:parent).ordered
      ordermaster.should_receive(:child).ordered

      mapper.map %w(code name chicness)

    end

    it "handles a default value" do
      mapper.field :name, default: "Steve"

      result = mapper.map [nil, nil]

      result.name.should eq("Steve")
    end

  end

  context "relationship mapping" do

    let(:mapper) { RowMapper.new(Product) }
    let(:cletus) { FactoryGirl.create :cletus }

    it "maps a many-valued relationship" do
      scarves = FactoryGirl.create :scarves
      mapper.field :categories, on: :name
      category_name = scarves.name

      result = mapper.map [category_name]

      result.categories.should include(scarves)
    end

    it "maps a single-valued relationship" do
      mapper.field :designer, on: :name
      name = cletus.name

      result = mapper.map [name]

      result.designer.should eq(cletus)
    end

    it "defaults to :id as the key" do
      mapper.field :designer
      id = cletus.id

      result = mapper.map [id]

      result.designer.should eq(cletus)
    end

    it "finds the key based on a custom key resolver" do
      nickname = "funny-fella"
      resolver = lambda do |v, product|
        v.should eq(nickname)
        product.should be_an_instance_of(Product)
        cletus.name
      end
      mapper.field :designer, on: :name, resolve_key_with: resolver

      result = mapper.map [nickname]

      result.designer.should eq(cletus)
    end

    it "uses a value resolver if configured to do so" do
      designer = cletus
      a_name = "some name"
      resolver = lambda do |name|
        name.should eq(a_name)
        designer
      end
      mapper.field :designer, resolve_with: resolver

      result = mapper.map [a_name]

      result.designer.should be(designer)
    end

    it "handles a default value" do
      mapper.field :designer, default: cletus

      result = mapper.map [nil]

      result.designer.should eq(cletus)
    end


    context "when configured to create related objects" do
      it "creates one if no related object was found" do
        creator = lambda do |id|
          d = Designer.new
          d.id = id
          d
        end
        id = 3664
        mapper.field :designer, create_with: creator

        result = mapper.map [id]

        result.designer.should_not be_nil
        result.designer.id.should eq(id)
      end

      it "doesn't create one if a related object was found" do
        creator = lambda do |id|
          fail("tried to create a related object when one was available")
        end

        mapper.field :designer, create_with: creator
        id = cletus.id

        result = mapper.map [id]

        result.designer.should eq(cletus)
      end

      it "doesn't fail if the creator is nil" do
        mapper.field :designer, create_with: nil
        id = cletus.id

        result = mapper.map [id]

        result.designer.should eq(cletus)
      end

      it "calls a resolver supplied as a method symbol" do
        # The scope of the closure below doesn't cover as much as I'd like, so I have to define these local variables.
        # I can't call eq(..), either.
        cid = cletus.id
        cle = cletus
        mapper.define_singleton_method(:resolve_for_cletus) do |id, product|
          fail("resolver wasn't called with correct key") if id != cid
          fail("resolver wasn't called with correct root object") if product.class != Product
          cle
        end
        mapper.field :designer, resolve_with: :resolve_for_cletus

        result = mapper.map [cid]

        result.designer.should eq(cletus)
      end

    end

  end

  context "nested objects" do

    let(:mapper) { RowMapper.new(Product) }

    it "maps a field in a nested object" do
      mapper.field :'variant.sku'
      sku = "XYZPDQ"

      result = mapper.map [sku]

      variant(result).sku.should eq(sku)
    end

    it "maps a single-valued relationship in a nested object" do
      user = FactoryGirl.create :stella
      mapper.field :'variant.user'
      id = user.id

      result = mapper.map [id]

      variant(result).user.should eq(user)
    end

    it "calls a resolver with the target and the root object" do
      handle = "somebody"
      user = FactoryGirl.create :stella
      key_resolver = lambda { |value, root|
        value.should eq(handle)
        root.should be_an_instance_of(Product)
        user.id
      }
      mapper.field :'variant.user', resolve_key_with: key_resolver

      result = mapper.map [handle]

      variant(result).user.should eq(user)
    end

    it "calls a nested-object sensor method with the correct nested object" do
      name = "cletus"
      decider = lambda { |designer|
        designer.name.should eq(name)
        true
      }
      mapper.field :'designer.name'
      mapper.is_present_if :designer, decider

      mapper.map [name]
    end

    it "deletes the nested object if the sensor method says to" do
      decider = lambda { |designer| false }
      mapper.field :'designer.name'
      mapper.is_present_if :designer, decider

      result = mapper.map %w(whatever)
      result.designer.should be_nil
    end

    it "retains the nested object if the sensor method says to" do
      decider = lambda { |designer| true }
      mapper.field :'designer.name'
      mapper.is_present_if :designer, decider

      result = mapper.map %w(whatever)
      result.designer.should be_an_instance_of(Designer)
    end

  end

  context "updating objects" do

    let(:mapper) { RowMapper.new(Designer) }


    it "updates objects based on a key" do
      mapper.update_on :id
      mapper.field :name

      user = Designer.create name: "stu"
      id = user.id

      result = mapper.map %W(#{id} Jerry)

      result.id.should eq(id)
      result.name.should eq("Jerry")
    end

    it "can update if the key isn't the first column" do
      user = Designer.create name: "stu"
      id = user.id

      mapper.field :name
      mapper.update_on :id

      result = mapper.map %W(Jerry #{id})

      result.id.should eq(id)
      result.name.should eq("Jerry")
    end

    it "returns a nil if no object was found" do
      mapper.update_on :id
      mapper.field :name
      result = mapper.map %W(hey Jerry)

      result.should be_nil
    end

    it "creates and then updates the record if configured that way" do
      mapper.update_on :id, can_create: true
      mapper.field :name

      mapper.map %W(3 Jerry)
      result = mapper.map %W(3 Steve)

      result.id.should eq(3)
      result.name.should eq("Steve")

    end

  end


  it "calls the before-save method" do
    class MyRowMapper < RowMapper
      def initialize
        super(Designer)
      end

      def before_save(designer)
        designer.name = "steve"
      end
    end

    mapper = MyRowMapper.new

    result = mapper.map []

    result.name.should eq("steve")
  end
end

describe "the row mapper DSL" do
  it "takes a block correctly" do
    mapper_with_block = RowMapper.new(Designer) { field :name }

    result = mapper_with_block.map %w(Cletus)

    result.name.should eq("Cletus")
  end

end

