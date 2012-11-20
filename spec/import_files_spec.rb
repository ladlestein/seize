require 'support/spec_helper'
require File.expand_path('../../lib/seize/job', __FILE__)


describe "the import job" do

  include TRR::Importer::Job

  let(:row_mapper) { double }
  let(:reject_buffer) { "" }
  let(:error_buffer) { "" }

  def invoke_import(input)
    import_file(StringIO.new(input), StringIO.new(reject_buffer), StringIO.new(error_buffer)) \
    {
        |row| row_mapper.map(row)
    }
  end

  context "good and bad rows" do

    let(:thing) { double }

    before(:each) do

      @good_row = "goodrow,good"
      @bad_row = "badrow,bad"
      @very_bad_row = "verybadrow,verybad"
    end


    def bad_row_expectations

      errors = double
      @bad_message = "That field was really bad"
      row_mapper.should_receive(:map).with(@bad_row.split ",").and_return(thing)
      thing.should_receive(:valid?).any_number_of_times.and_return(false)
      thing.should_receive(:errors).any_number_of_times.and_return(errors)
      errors.should_receive(:full_messages).any_number_of_times.and_return([@bad_message])
      thing.should_receive(:save!).never
    end


    it "imports a good row" do

      row_mapper.should_receive(:map).with(@good_row.split ",").and_return(thing)
      thing.should_receive(:valid?).at_least(:once).and_return(true)
      thing.should_receive(:save!)

      invoke_import(@good_row)
    end

    it "doesn't import a bad row" do

      bad_row_expectations

      invoke_import(@bad_row)
    end

    it "writes the bad row to the rejects file" do


      bad_row_expectations

      invoke_import(@bad_row)

      reject_buffer.chomp.should eq(@bad_row)
    end

    it "writes the errors to the errors file" do

      bad_row_expectations

      invoke_import(@bad_row)

      error_buffer.should include(@bad_message)
    end

    it "reports the right errors for each row" do


      all_rows = @bad_row + "\n" + @good_row + "\n" + @very_bad_row

      thing1 = double
      thing2 = double
      thing3 = double

      errors1 = double
      errors3 = double
      bad_messages = ["it was wrong"]
      very_bad_messages = ["what a terrible row!", "your shirt is untucked"]
      row_mapper.should_receive(:map).with(@bad_row.split ",").and_return(thing1)
      row_mapper.should_receive(:map).with(@good_row.split ",").and_return(thing2)
      row_mapper.should_receive(:map).with(@very_bad_row.split ",").and_return(thing3)

      thing1.should_receive(:valid?).any_number_of_times.and_return(false)
      thing2.should_receive(:valid?).any_number_of_times.and_return(true)
      thing3.should_receive(:valid?).any_number_of_times.and_return(false)

      thing1.should_receive(:errors).any_number_of_times.and_return(errors1)
      thing3.should_receive(:errors).any_number_of_times.and_return(errors3)
      errors1.should_receive(:full_messages).any_number_of_times.and_return(bad_messages)
      errors3.should_receive(:full_messages).any_number_of_times.and_return(very_bad_messages)
      thing.should_receive(:save!).never

      thing2.should_receive(:save!)

      invoke_import(all_rows)

      row_errors = error_buffer.split("\n")
      row_errors.length.should be(2)
      row_errors[0].should include(*bad_messages)
      row_errors[1].should include(*very_bad_messages)
      row_errors[0].should_not include(*very_bad_messages)
      row_errors[1].should_not include(*bad_messages)

      row_rejects = reject_buffer.split("\n")
      row_rejects.length.should be(2)
      row_rejects[0].should eq(@bad_row)
      row_rejects[1].should eq(@very_bad_row)
    end

  end

  it "reports errors when no object was returned" do
    row_mapper.stub(:map).and_return nil

    invoke_import("whatever")

    reject_buffer.chomp.should eq("whatever")
    error_buffer.should include(TRR::Importer::Job::NO_OBJECT_FOUND)
  end
end