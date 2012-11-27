require 'tsort'

module Seize

  class FieldMapping
    attr_reader :name
    attr_reader :mapper

    def initialize(name, mapper)
      @name = name
      @mapper = mapper
    end

    def depends_on
      @mapper.depends_on
    end

    def map(value, root)
      @mapper.map(value, root)
    end
  end

  class RowMapper

    def initialize(target_class, &block)
      @mappings = []
      @sensors = []
      @current_mapping_target = @mappings

      @target_class = target_class
      instance_eval &block if block_given?
    end

    def cell(&block)
      cell_mappers = []
      @current_mapping_target = cell_mappers
      instance_eval &block
      @mappings << cell_mappers
      @current_mapping_target = @mappings
    end

    def create_field_mapping(name, options)
      options = options.clone
      [:resolve_key_with, :create_with, :resolve_with].each do | symbol |
        options[symbol] = convert_to_method_if_needed(options[symbol]) if options[symbol]
      end
      mapper = ClassAccessor.new(@target_class).field(name, options)
      FieldMapping.new(name, mapper)
    end

    def field(name, options = {})
      @current_mapping_target << create_field_mapping(name, options)
    end

    def update_on(name, options = {})
      @key_field_name = name
      @can_create = options[:can_create]
      field(name, options)
    end

    def is_present_if(nested_object_name, func)
      callable = convert_to_method_if_needed(func)
      sensor = ClassAccessor.new(@target_class).nested_object_sensor(nested_object_name, callable)
      @sensors << sensor
    end

    def convert_to_method_if_needed(callable)
      if callable.class == Symbol

        target = method(callable)
        if target.arity == 2
          lambda do | arg1, arg2 |
            target.call(arg1, arg2)
          end
        else
          lambda do | arg1, arg2 = nil |
            target.call(arg1)
          end
        end

      else
        callable
      end
    end

    def ignored
      @mappings << nil
    end

    def find_by_key(operation)
      value = operation.value_after_resolution(nil)
      finder_name = "find_by_#@key_field_name"
      @target_class.public_send(finder_name, value)
    end

    def map(row)
      operations = TopologicallySortableMultiHash.new
      row.zip(@mappings).each do |cell, mapping_or_mappings|
        if mapping_or_mappings

          value = cell.class == Array ? cell[1] : cell # CSV may return a header w/the value, but we don't need it.

          mappings = mapping_or_mappings.class == Array ? mapping_or_mappings : [mapping_or_mappings]
          mappings.each { | mapping |
            operations[mapping.name] << MappingOperation.new(value, mapping.mapper)
          }

        end
      end
      if @key_field_name
        key_operation = (operations.delete @key_field_name)[0]
        root = find_by_key(key_operation)
        if @can_create && root.nil?
          root = @target_class.new
          key_operation.perform_on(root)
        end
      else
        root = @target_class.new
      end
      if root
        operations.tsort.each do | field_name |
          operations[field_name].each { | operation | operation.perform_on(root) }
        end
      end
      sense_nested_objects(root)
      before_save(root)
      root
    end

    def sense_nested_objects(root)
      @sensors.each { | sensor | sensor.delete_if_not_sensed(root) }
    end

    def before_save(root)
      # override me!
    end

  end

  class NestedObjectSensor
    attr_reader :name

    def initialize(nested_object_name, callable)
      @name = nested_object_name
      @callable = callable
    end

    def delete_if_not_sensed(root)
      nested_object = read(root)
      unless @callable.call(nested_object)
        clear(root)
      end
    end

  end

  class TopologicallySortableMultiHash < Hash
    include TSort

    def initialize
      super {|k,v| k[v] = []}
    end

    alias tsort_each_node each_key

    def tsort_each_child(node, &block)
      fetch(node).map {| operation |
        operation.depends_on
      }.reject {| key |
        key.nil?}.each(&block)
    end

  end

  class MappingOperation
    attr_reader :value, :mapper

    def initialize(value, mapper)
      @value = value
      @mapper = mapper
    end

    def depends_on
      @mapper.depends_on
    end

    def perform_on(root)
      @mapper.map(value, root)
    end

    def value_after_resolution(root)
      @mapper.value_after_resolution(@value, root)
    end

  end

  class ClassAccessor

    def initialize(target_class)
      @target_class = target_class
    end

    def field(name, options = {})
      prefix, remainder = split_if_compound(name)
      if prefix
        association = association_for(prefix)
        klass = association.klass
        mapper = ClassAccessor.new(klass).field(remainder, options)
        mapper = wrap_mapper(prefix, mapper)
      else
        mapper = create_field_mapper(remainder, options)
      end
      mapper
    end

    def split_if_compound(name)
      if compound_name?(name)
        segs = name.to_s.split(".")
        [segs[0], segs.drop(1).join(".")]
      else
        [nil, name]
      end
    end

    def compound_name?(name)
      name.to_s.index "."
    end

    def wrap_mapper(name, nested_mapper)
      mapper = NestedObjectFieldMapper.new(name, nested_mapper)
      extend_for_relationship(mapper, name)
    end

    def create_field_mapper(name, options)
      association = association_for(name)
      if association
        related_class = association.klass
        mapper = RelationshipFieldMapper.new(name.to_s, related_class, options)
        extend_for_relationship(mapper, name)
      else
        mapper = FieldMapper.new(name.to_s, options)
        mapper.extend(ScalarAccess)
      end
      mapper
    end

    def nested_object_sensor(nested_object_name, callable)
      sensor = NestedObjectSensor.new(nested_object_name.to_s, callable)
      extend_for_relationship(sensor, nested_object_name)
    end

    def extend_for_relationship(accessor, name)
      association = association_for(name)
      access_module = association.collection? ? CollectionRelationAccess : ScalarRelationAccess
      accessor.extend(access_module)
      accessor
    end

    def association_for(name)
      association = @target_class.reflect_on_association(name.to_sym)
      unless association
        plural_name = ActiveSupport::Inflector.pluralize name
        association = @target_class.reflect_on_association(plural_name.to_sym)
      end
      association
    end


  end

  module ScalarAccess

    def read(target)
      target.public_send @name
    end

    def write(value, target)
      target.public_send @name + "=", value
    end

    def clear(target)
      write(nil, target)
    end

  end

  module ScalarRelationAccess
    include ScalarAccess

    def build(target)
      target.public_send "build_#@name"
    end

  end

  module CollectionRelationAccess

    def collection_name
      ActiveSupport::Inflector.pluralize @name
    end

    def collection(target)
      target.public_send collection_name
    end

    def clear(target)
      collection(target).clear
    end

    def read(target)
      collection = collection(target)
      collection[0]
    end

    def build(target)
      collection = collection(target)
      collection.build
    end

    def write(value, target)
      collection = collection(target)

      # Write to the collection, unless the value is nil.
      # Writing nil to a persistent collection is surely an error.
      # But maybe it would be better to raise an error? Hard to say.
      collection << value unless value.nil?
    end
  end

  class FieldMapper

    attr_reader :name
    attr_reader :depends_on
    attr_reader :default
    attr_reader :resolve_with
    attr_reader :options

    def initialize(name, options)
      @name = name
      @options = options
      @depends_on = options[:depends_on]
      @default = options[:default]
      @resolve_with = options[:resolve_with]
    end

    def call(target, value, root)
      if target.arity == 2
        target.call(value, root)
      else
        target.call(value)
      end
    end

    def value_after_default(value)
      value || @default
    end

    def value_after_resolution(value, root)
      @resolve_with ? call(@resolve_with, value, root) : value
    end

    def map(value, target, root = target)
      value = value_after_resolution(value, root)
      value = value_after_default(value)
      write(value, target)
    end

  end

  class RelationshipFieldMapper < FieldMapper

    def initialize(name, klass, options)
      super(name, options)
      @klass = klass
      @key = options[:on] || :id
      @resolve_key_with = options[:resolve_key_with]
      @create_with = options[:create_with]
    end

    def map(key, target, root = target)
      if @resolve_with
        super(key, target, root)
      else
        key = call(@resolve_key_with, key, root) if @resolve_key_with
        related_object = @klass.public_send "find_by_#@key", key
        related_object ||= call(@create_with, key, root) if @create_with
        super(related_object, target, root)
      end
    end
  end

  class NestedObjectFieldMapper < FieldMapper

    def initialize(nested_name, nested_mapper)
      super(nested_name, nested_mapper.options)
      @nested_mapper = nested_mapper
    end

    def map(value, target, root = target)
      nested_target = read(target) || build(target)
      @nested_mapper.map(value, nested_target, root)
    end

  end
end
