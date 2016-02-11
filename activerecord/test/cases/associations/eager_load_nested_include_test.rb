require 'cases/helper'
require 'models/post'
require 'models/tag'
require 'models/author'
require 'models/comment'
require 'models/category'
require 'models/categorization'
require 'models/tagging'

class ShapeExpression < ActiveRecord::Base
  belongs_to :shape, :polymorphic => true
  belongs_to :paint, :polymorphic => true
end

class Circle < ActiveRecord::Base
  has_many :shape_expressions, :as => :shape
end
class Square < ActiveRecord::Base
  has_many :shape_expressions, :as => :shape
end
class Triangle < ActiveRecord::Base
  has_many :shape_expressions, :as => :shape
end
class PaintColor  < ActiveRecord::Base
  has_many   :shape_expressions, :as => :paint
  belongs_to :non_poly, :foreign_key => "non_poly_one_id", :class_name => "NonPolyOne"
end
class PaintTexture < ActiveRecord::Base
  has_many   :shape_expressions, :as => :paint
  belongs_to :non_poly, :foreign_key => "non_poly_two_id", :class_name => "NonPolyTwo"
end
class NonPolyOne < ActiveRecord::Base
  has_many :paint_colors
end
class NonPolyTwo < ActiveRecord::Base
  has_many :paint_textures
end


class EagerLoadPolyAssocsTest < ActiveRecord::TestCase
  NUM_SIMPLE_OBJS = 50
  NUM_SHAPE_EXPRESSIONS = 100

  setup do
    cache = {}
    1.upto(NUM_SIMPLE_OBJS) do
      [Circle, Square, Triangle, NonPolyOne, NonPolyTwo].each do |klass|
        cache[klass] ||= []
        cache[klass] << klass.create!
      end
    end
    1.upto(NUM_SIMPLE_OBJS) do
      cache[PaintColor] ||= []
      cache[PaintColor] << PaintColor.create!(:non_poly_one_id => cache[NonPolyOne].sample.id)
      cache[PaintTexture] ||= []
      cache[PaintTexture] << PaintTexture.create!(:non_poly_two_id => cache[NonPolyTwo].sample.id)
    end
    1.upto(NUM_SHAPE_EXPRESSIONS) do
      shape = [Circle, Square, Triangle].sample
      paint = [PaintColor, PaintTexture].sample
      ShapeExpression.create!(:shape_type => shape.to_s, :shape_id => cache[shape].sample.id,
                              :paint_type => paint.to_s, :paint_id => cache[paint].sample.id)
    end
  end

  teardown do
    [Circle, Square, Triangle, PaintColor, PaintTexture,
     ShapeExpression, NonPolyOne, NonPolyTwo].each(&:delete_all)
  end

  def test_include_query
    res = ShapeExpression.all.merge!(:includes => [ :shape, { :paint => :non_poly } ]).to_a
    assert_equal NUM_SHAPE_EXPRESSIONS, res.size
    assert_queries(0) do
      res.each do |se|
        assert_not_nil se.paint.non_poly, "this is the association that was loading incorrectly before the change"
        assert_not_nil se.shape, "just making sure other associations still work"
      end
    end
  end

  def test_deeply_nested_include_query
    expression = nil
    assert_nothing_raised do
      expression = ShapeExpression.includes(paint: {non_poly: [:paint_colors, :paint_textures]}).first
    end
    assert_no_queries do
      case non_poly = expression.paint.non_poly
      when NonPolyOne
        non_poly.paint_colors
      when NonPolyTwo
        non_poly.paint_textures
      end
    end
  end
end

class EagerLoadNestedIncludeWithMissingDataTest < ActiveRecord::TestCase
  def setup
    @davey_mcdave = Author.create(:name => 'Davey McDave')
    @first_post = @davey_mcdave.posts.create(:title => 'Davey Speaks', :body => 'Expressive wordage')
    @first_comment = @first_post.comments.create(:body => 'Inflamatory doublespeak')
    @first_categorization = @davey_mcdave.categorizations.create(:category => Category.first, :post => @first_post)
  end

  teardown do
    @davey_mcdave.destroy
    @first_post.destroy
    @first_comment.destroy
    @first_categorization.destroy
  end

  def test_missing_data_in_a_nested_include_should_not_cause_errors_when_constructing_objects
    assert_nothing_raised do
      # @davey_mcdave doesn't have any author_favorites
      includes = {:posts => :comments, :categorizations => :category, :author_favorites => :favorite_author }
      Author.all.merge!(:includes => includes, :where => {:authors => {:name => @davey_mcdave.name}}, :order => 'categories.name').to_a
    end
  end
end
