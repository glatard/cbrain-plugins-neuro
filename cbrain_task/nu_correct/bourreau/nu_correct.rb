
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

# A subclass of ClusterTask to run NuCorrect.
class CbrainTask::NuCorrect < ClusterTask

  Revision_info=CbrainFileRevision[__FILE__] #:nodoc:

  include RestartableTask
  include RecoverableTask

  def setup #:nodoc:
    params     = self.params || {}
    lt         = params[:launch_table]["0"]

    infile = Userfile.find(lt[:in_id])
    infile.sync_to_cache
    fullpath   = infile.cache_full_path
    basename   = fullpath.basename
    safe_symlink(fullpath,basename)

    self.results_data_provider_id ||= infile.data_provider_id

    maskfile = lt[:use_mask] == "1" ? Userfile.find(lt[:mk_id]) : nil
    if maskfile
      maskfile.sync_to_cache
      maskfull = maskfile.cache_full_path
      maskbase = maskfull.basename
      safe_symlink(maskpath,maskbase)
    end

    true
  end

  def cluster_commands #:nodoc:
    params     = self.params || {}
    lt         = params[:launch_table]["0"]

    infile     = Userfile.find(lt[:in_id])
    basename   = infile.cache_full_path.basename

    maskfile   = lt[:use_mask] == "1" ? Userfile.find(lt[:mk_id]) : nil
    maskbase   = maskfile ? maskfile.cache_full_path.basename : nil

    outname  = "nu-correct-#{self.run_id}-#{basename}"

    command  = "nu_correct"
    command += " -mask       #{shell_escape(maskbase)}"             if maskbase
    command += " -distance   #{shell_escape(params[:distance])}"
    command += " -iterations #{shell_escape(params[:iterations])}"
    command += " -stop       #{shell_escape(params[:stop])}"
    command += " -shrink     #{shell_escape(params[:shrink])}"
    command += " -fwhm       #{shell_escape(params[:fwhm])}"
    command += " -normalize_field"                                  if params[:normalize_field] == "1"
    command += " #{shell_escape(basename)}"
    command += " #{shell_escape(outname)}"

    [
      "#{command}\n"
    ]
  end

  def save_results #:nodoc:
    params     = self.params || {}
    lt         = params[:launch_table]["0"]

    infile     = Userfile.find(lt[:in_id])
    basename   = infile.cache_full_path.basename
    outname    = "nu-correct-#{self.run_id}-#{basename}"

    unless File.exist?(outname)
      self.addlog("Cannot find expected output file '#{outname}'.")
      return false
    end

    outfile = safe_userfile_find_or_new(MincFile,
      :name             => outname,
      :data_provider_id => self.results_data_provider_id
    )
    outfile.save!
    outfile.move_to_child_of(infile)
    outfile.cache_copy_from_local_file(outname)

    params[:outfile_id] = outfile.id
    self.addlog_to_userfiles_these_created_these( infile, outfile )

    true
  end

  private

  # This utility method escapes properly any string such that
  # it becomes a literal in a bash command; the string returned
  # will include the surrounding single quotes.
  #
  #   shell_escape("Mike O'Connor")
  #
  # returns
  #
  #   'Mike O'\''Connor'
  def shell_escape(s) #:nodoc:
    s.to_s.bash_escape(true)  # in config/initializers/core_extentions/string.rb
  end


end

