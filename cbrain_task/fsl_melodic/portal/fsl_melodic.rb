
#
# CBRAIN Project
#
# Copyright (C) 2008-2012
# The Royal Institution for the Advancement of Learning
# McGill University
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

# A subclass of CbrainTask to launch FslBet.
#
# Original author: Tristan Glatard
class CbrainTask::FslMelodic < PortalTask

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  task_properties :readonly_input_files, :use_parallelizer

  def self.default_launch_args #:nodoc:
    {
      :output_name => "melodic-output"
    }
  end

  def usage
    "You MUST select:
     * an FSL design file, with extension .fsf or CBRAIN type FSLDesignFile.
     * a CSV file containing pairs of Nifti or MINC file names, separated by commas.
     --- The corresponding files must be registered in CBRAIN and you must have access to them.
     --- The file type (MINC or Nifti) is determined based on the file extension (.mnc, .nii or .nii.gz).
     --- The first file in the pair will be treated as a functional file.
     --- The second file in the pair will be treated as an anatomical file.
    "
  end
  
  def before_form #:nodoc:
    # Checks input files
    parse_input_files
    # Parses CSV file
    parse_csv_file   
    # Parses design file
    parse_design_file
    #
    ""
  end

  def after_form #:nodoc:
    before_form if ! params[:functional_file_ids].present? # happens when the API is used
    params_errors.add(params[:output_name], "is not a legal output filename") unless Userfile.is_legal_filename?(params[:output_name])
    params.delete :regstandard_file_id unless params[:custom_regstandard] == "1"    
    output_name = ( (! params[:output_name].present?) || (! params[:output_name].strip.present?) ) ? output_name : params[:output_name].strip
    ""
  end

  def final_task_list #:nodoc:    
    mytasklist = []
    if params[:icaopt] == "1" # creates 1 task per functional file
      functional_file_ids = params[:functional_file_ids]
      structural_file_ids = params[:structural_file_ids]

      functional_file_ids.each_with_index do |id,idx|
        task=self.dup # not .clone, as of Rails 3.1.10
        task.params[:functional_file_ids] = [ id ]
        task.params[:structural_file_ids] = [ structural_file_ids[idx] ]
        set_task_parameters(task)
        mytasklist << task
      end

    else # creates only 1 task
      task=self.dup # not .clone, as of Rails 3.1.10
      set_task_parameters(task)
      mytasklist << task
    end
    return mytasklist
  end


  def untouchable_params_attributes #:nodoc:
    { :inputfile_id => true, :output_name => true, :outfile_id => true}
  end

  private

  ############################################
  ## Parsing methods, called in before_form ##
  ############################################
  
  def parse_input_files
    ids    = params[:interface_userfile_ids]
    ids.each do |id|
      u = Userfile.find(id) rescue nil
      cb_error "Error: input file #{id} doesn't exist." unless u
      cb_error "Error: '#{u.name}' does not seem to be a single file." unless u.is_a?(SingleFile)
      cb_error "Error: found a #{u.type}. \n #{usage}" unless ( u.is_a?(CSVFile) || u.is_a?(FSLDesignFile) || u.name.end_with?(".csv") || u.name.end_with?(".fsf"))
      if u.is_a?(FSLDesignFile) || u.name.end_with?(".fsf")
        cb_error "Error: you may select only 1 design file. \n #{usage}" unless params[:design_file_id].nil?
        params[:design_file_id] = id
      end
      if u.is_a?(CSVFile) || u.name.end_with?(".csv")
        cb_error "Error: you may select only 1 CSV file. \n #{usage}" unless params[:csv_file_id].nil?
        params[:csv_file_id] = id
      end
    end
    cb_error "Error: design file missing. \n #{usage}" if params[:design_file_id].nil?
    cb_error "Error: CSV file missing. \n #{usage}" if params[:csv_file_id].nil?
  end
  
  def parse_csv_file
    params[:structural_file_ids] = Array.new
    params[:functional_file_ids] = Array.new
    
    csv_file  = Userfile.find(params[:csv_file_id])
    csv_file.sync_to_cache unless csv_file.is_locally_synced?
    
    lines = ""
    begin
      lines    = csv_file.becomes(CSVFile).create_csv_array("\"",",")
    rescue => ex
      cb_error "Cannot create array from CSV file (#{ex.message}). Maybe the format of your CSV file is wrong."
    end
    
    lines.each do |line|
      cb_error "Error: lines in CSV file must contain two elements separated by a comma (wrong format: #{line})." unless line.size == 2
      line.each_with_index do |file_name,index|
        file_name.strip!
        # Checks files in line
        cb_error "Error: file #{file_name} (present in #{csv_file.name}) doesn't look like a Nifti or MINC file (must have a .mnc, .nii or .nii.gz extension)" unless ( file_name.end_with?(".nii") || file_name.end_with?(".nii.gz") || file_name.end_with?(".mnc") )
        file_array   = Userfile.where(:name => file_name)
        current_user = User.find(self.user_id)
        file_array   = Userfile.find_accessible_by_user(file_array.map { |x| x.id }, current_user) rescue [] # makes sure that files accessible by the user are selected
        cb_error "Error: file #{file_name} (present in #{csv_file.name}) not found!" unless file_array.size > 0
        cb_error "Error: multiple files found for #{file_name} (present in #{csv_file.name})" if file_array.size > 1 # this shouldn't happen.
        # Assigns files
        file_id = file_array.first.id
        if index == 0
          params[:functional_file_ids] << file_id
        else
          params[:structural_file_ids] << file_id
        end
      end
    end
  end

  def parse_design_file
    design_file = Userfile.find(params[:design_file_id])
    design_file.sync_to_cache unless design_file.is_locally_synced?
    design_file_content = File.read(design_file.cache_full_path)
    
    option_values = get_option_values_from_design_file_content(design_file_content)
    options = ["tr","ndelete","filtering_yn","brain_thresh",
               "mc","te","bet_yn","smooth","st","norm_yn",
               "temphp_yn","templp_yn","motionevs","bgimage",
               "reghighres_yn","reghighres_search","reghighres_dof",
               "regstandard_yn","regstandard_search","regstandard_dof",
               "regstandard_nonlinear_yn","regstandard_nonlinear_warpres",
               "regstandard_res","varnorm","dim_yn","dim","thresh_yn",
               "mmthresh","ostats","icaopt","analysis","paradigm_hp",
               "npts","totalVoxels"]
    options.each { |option| params[option.to_sym] = option_values[option] }
    
    params[:template_files]                = get_template_files
    
    # initializes parameters that are not in the design file
    params[:tr_auto]   = params[:tr_auto].present? ? params[:tr_auto] : "1"
    params[:npts_auto] = params[:npts_auto].present? ? params[:npts_auto] : "1"
    params[:totalvoxels_auto] = params[:totalvoxels_auto].present? ? params[:totalvoxels_auto] : "1"
  end


  def get_template_files
    template_files = []
    current_user = User.find(self.user_id)
    user_tags = current_user.available_tags.select {|t| t.name =~ /TEMPLATE/i}
    user_tags.each do |tag|
      user_files ||= Userfile.find_all_accessible_by_user(current_user)
      template_files.concat user_files.select { |u| u.tag_ids.include? tag.id }
    end
    return template_files.map { |f| [f.name,f.id.to_s]}
  end
  
  
  def get_option_values_from_design_file_content design_file_content
    options = Hash.new
    design_file_content.each_line do |line|
      line.strip!
      line.downcase!
      next if line.start_with? "#"
      tokens = line.split(" ")
      options[(tokens[1].downcase.split(/[(,)]/))[1]] = tokens[2] if tokens[0] == "set"
    end
    return options
  end


  ###########################
  ## Other utility methods ##
  ###########################
  
  def set_task_parameters task
    ids = []

    ids = task.params[:functional_file_ids].dup 
    ids.concat task.params[:structural_file_ids] 
    ids << task.params[:design_file_id]
    ids << task.params[:regstandard_file_id] if task.params[:regstandard_file_id].present?

    description_strings = []
    if task.params[:functional_file_ids].present?
      task.params[:functional_file_ids].each do |id|
        description_strings << Userfile.find(id).name+" "
      end
    end

    task.params[:task_file_ids] = ids
    task.description = description_strings.join if task.description.blank?

    task.params.delete :interface_userfile_ids
  end

  
end

