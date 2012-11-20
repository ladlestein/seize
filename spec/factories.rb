FactoryGirl.define do

  factory :scarves, :class => Category do
    name "Scarves"
  end

  factory :cletus, :class => Designer do
    name "Cletus"
  end

  factory :stella, :class => User do
    name "Stella"
  end
end