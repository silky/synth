--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

package PortScan.Packages is

   --  This can only be executed if a full scan has already occurred.
   --  This is a deep scan of existing packages that is intended to be run
   --  just prior to building a repository. It is also executed before
   --  a full bulk run (in which case it will not be run before rebuilding
   --  the repository.
   procedure clean_repository (repository : String);

   --  If performing a limited build run (likely 99% of the use cases), only
   --  the queued packages will be checked.  The checks are limited to finding
   --  options changes and dependency changes.  Obsolete packages (related or
   --  unrelated to upcoming build) are not removed; this would occur in
   --  clean_repository().  These old packages will not interfere at this step.
   procedure limited_sanity_check (repository : String);

   --  A public component of limited_sanity_check that can be used to check
   --  individual packages (it's not queue based)
   procedure limited_package_check (repository : String; id : port_id;
                                    pkg_exists : out Boolean);

   --  Iterate through the final build queue to remove any packages that
   --  match the current package names
   procedure remove_queue_packages (repository : String);

   --  This procedure empties the given repository without discrimination.
   --  (Well, it's limited to "*.txz" matches, but normally that's everything)
   procedure wipe_out_repository (repository : String);

private

   stored_packages : package_crate.Map;

   --  This function returns "True" if the scanned options exactly match
   --  the options in the already-built package.  Usually it's already known
   --  that a package exists before the function is called, but an existence
   --  check will be performed just in case (failure returns "False")
   function passed_option_check (repository : String; id : port_id;
                                 skip_exist_check : Boolean := False)
                                 return Boolean;

   --  This function returns "True" if the scanned dependencies match exactly
   --  what the current ports tree has.
   function passed_dependency_check (repository : String; id : port_id;
                                     skip_exist_check : Boolean := False)
                                     return Boolean;

   procedure scan_repository (repository : String);
   procedure nextline (lineblock, firstline : out JT.Text);


end PortScan.Packages;