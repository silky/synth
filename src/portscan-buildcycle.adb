--  This file is covered by the Internet Software Consortium (ISC) License
--  Reference: ../License.txt

with Ada.Calendar.Arithmetic;
with Ada.Calendar.Formatting;
with Ada.Direct_IO;
with Replicant.Platform;

package body PortScan.Buildcycle is

   package ACA renames Ada.Calendar.Arithmetic;
   package ACF renames Ada.Calendar.Formatting;
   package REP renames Replicant;


   ----------------------
   --  initialize_log  --
   ----------------------
   function initialize_log (id : builders) return Boolean
   is
      FA    : access TIO.File_Type;
      H_ENV : constant String := "Environment";
      H_OPT : constant String := "Options";
      CFG1  : constant String := "/etc/make.conf";
      CFG2  : constant String := "/etc/mk.conf";
      UNAME : constant String := JT.USS (uname_mrv);
      BENV  : constant String := get_environment (id);
      COPTS : constant String := get_options_configuration (id);
      PTVAR : JT.Text         := get_port_variables (id);
   begin
      trackers (id).dynlink.Clear;
      trackers (id).head_time := CAL.Clock;
      declare
         log_path : constant String := log_name (trackers (id).seq_id);
      begin
         if AD.Exists (log_path) then
            AD.Delete_File (log_path);
         end if;
         TIO.Create (File => trackers (id).log_handle,
                     Mode => TIO.Out_File,
                     Name => log_path);
         FA := trackers (id).log_handle'Access;
      exception
         when error : others =>
            raise cycle_log_error
              with "failed to create log " & log_path;
      end;

      TIO.Put_Line (FA.all, "=> Building " &
                      get_catport (all_ports (trackers (id).seq_id)));
      TIO.Put_Line (FA.all, "Started : " & timestamp (trackers (id).head_time));
      TIO.Put      (FA.all, "Platform: " & UNAME);
      if BENV = discerr then
         TIO.Put_Line (FA.all, LAT.LF & "Environment definition failed, " &
                         "aborting entire build");
         return False;
      end if;
      TIO.Put_Line (FA.all, LAT.LF & log_section (H_ENV, True));
      TIO.Put      (FA.all, BENV);
      TIO.Put_Line (FA.all, log_section (H_ENV, False) & LAT.LF);
      TIO.Put_Line (FA.all, log_section (H_OPT, True));
      TIO.Put      (FA.all, COPTS);
      TIO.Put_Line (FA.all, log_section (H_OPT, False) & LAT.LF);

      dump_port_variables (id => id, content => PTVAR);

      case software_framework is
         when ports_collection =>
            TIO.Put_Line (FA.all, log_section (CFG1, True));
            TIO.Put      (FA.all, dump_make_conf (id, CFG1));
            TIO.Put_Line (FA.all, log_section (CFG1, False) & LAT.LF);
         when pkgsrc =>
            TIO.Put_Line (FA.all, log_section (CFG2, True));
            TIO.Put      (FA.all, dump_make_conf (id, CFG2));
            TIO.Put_Line (FA.all, log_section (CFG2, False) & LAT.LF);
      end case;
      return True;

   end initialize_log;


   --------------------
   --  finalize_log  --
   --------------------
   procedure finalize_log (id : builders) is
   begin
      TIO.Put_Line (trackers (id).log_handle, log_section ("Termination", True));
      trackers (id).tail_time := CAL.Clock;
      TIO.Put_Line (trackers (id).log_handle,
                    "Finished: " & timestamp (trackers (id).tail_time));
      TIO.Put_Line (trackers (id).log_handle,
                    log_duration (start => trackers (id).head_time,
                                  stop  => trackers (id).tail_time));
      TIO.Close (trackers (id).log_handle);
   end finalize_log;


   --------------------
   --  log_duration  --
   --------------------
   function log_duration (start, stop : CAL.Time) return String
   is
      raw : JT.Text := JT.SUS ("Duration:");
      diff_days : ACA.Day_Count;
      diff_secs : Duration;
      leap_secs : ACA.Leap_Seconds_Count;
      use type ACA.Day_Count;
   begin
      ACA.Difference (Left    => stop,
                      Right   => start,
                      Days    => diff_days,
                      Seconds => diff_secs,
                      Leap_Seconds => leap_secs);
      if diff_days > 0 then
         if diff_days = 1 then
            JT.SU.Append (raw, " 1 day and " &
                            ACF.Image (Elapsed_Time => diff_secs));
         else
            JT.SU.Append (raw, diff_days'Img & " days and " &
                            ACF.Image (Elapsed_Time => diff_secs));
         end if;
      else
         JT.SU.Append (raw, " " & ACF.Image (Elapsed_Time => diff_secs));
      end if;
      return JT.USS (raw);
   end log_duration;


   ------------------------
   --  elapsed_HH_MM_SS  --
   ------------------------
   function elapsed_HH_MM_SS (start, stop : CAL.Time) return String
   is
      diff_days : ACA.Day_Count;
      diff_secs : Duration;
      leap_secs : ACA.Leap_Seconds_Count;
      secs_per_hour : constant Integer := 3600;
      total_hours   : Integer;
      total_minutes : Integer;
      work_hours    : Integer;
      work_seconds  : Integer;
      use type ACA.Day_Count;
   begin
      ACA.Difference (Left    => stop,
                      Right   => start,
                      Days    => diff_days,
                      Seconds => diff_secs,
                      Leap_Seconds => leap_secs);
      --  Seems the ACF image is shit, so let's roll our own.  If more than
      --  100 hours, change format to "HHH:MM.M"

      work_seconds := Integer (diff_secs);
      total_hours  := work_seconds / secs_per_hour;
      total_hours  := total_hours + Integer (diff_days) * 24;

      if total_hours < 24 then
         if work_seconds < 0 then
            return "--:--:--";
         else
            work_seconds := work_seconds - (total_hours * secs_per_hour);
            total_minutes := work_seconds / 60;
            work_seconds := work_seconds - (total_minutes * 60);
            return
              JT.zeropad (total_hours, 2) & LAT.Colon &
              JT.zeropad (total_minutes, 2) & LAT.Colon &
              JT.zeropad (work_seconds, 2);
         end if;
      elsif total_hours < 100 then
         if work_seconds < 0 then
            return JT.zeropad (total_hours, 2) & ":00:00";
         else
            work_hours := work_seconds / secs_per_hour;
            work_seconds := work_seconds - (work_hours * secs_per_hour);
            total_minutes := work_seconds / 60;
            work_seconds := work_seconds - (total_minutes * 60);
            return
              JT.zeropad (total_hours, 2) & LAT.Colon &
              JT.zeropad (total_minutes, 2) & LAT.Colon &
              JT.zeropad (work_seconds, 2);
         end if;
      else
         if work_seconds < 0 then
            return JT.zeropad (total_hours, 3) & ":00.0";
         else
            work_hours := work_seconds / secs_per_hour;
            work_seconds := work_seconds - (work_hours * secs_per_hour);
            total_minutes := work_seconds / 60;
            work_seconds := (work_seconds - (total_minutes * 60)) * 10 / 60;
            return
              JT.zeropad (total_hours, 3) & LAT.Colon &
              JT.zeropad (total_minutes, 2) & '.' &
              JT.int2str (work_seconds);
         end if;
      end if;
   end elapsed_HH_MM_SS;


   -------------------
   --  elapsed_now  --
   -------------------
   function elapsed_now return String is
   begin
      return elapsed_HH_MM_SS (start => start_time, stop => CAL.Clock);
   end elapsed_now;


   -----------------------------
   -- generic_system_command  --
   -----------------------------
   function generic_system_command (command : String) return JT.Text
   is
      content : JT.Text;
      status  : Integer;
   begin
      content := Unix.piped_command (command, status);
      if status /= 0 then
         raise cycle_cmd_error with "cmd: " & command &
           " (return code =" & status'Img & ")";
      end if;
      return content;
   end generic_system_command;


   ---------------------
   --  set_uname_mrv  --
   ---------------------
   procedure set_uname_mrv
   is
      --  valid for all platforms
      command : constant String := "/usr/bin/uname -mrv";
   begin
      uname_mrv := generic_system_command (command);
   exception
      when others =>
         uname_mrv := JT.SUS (discerr);
   end set_uname_mrv;


   ----------------
   --  get_root  --
   ----------------
   function get_root (id : builders) return String
   is
      id_image     : constant String := Integer (id)'Img;
      suffix       : String := "/SL00";
   begin
      if id < 10 then
         suffix (5) := id_image (2);
      else
         suffix (4 .. 5) := id_image (2 .. 3);
      end if;
      return JT.USS (PM.configuration.dir_buildbase) & suffix;
   end get_root;


   -----------------------
   --  get_environment  --
   -----------------------
   function get_environment (id : builders) return String
   is
      root    : constant String := get_root (id);
      command : constant String := chroot & root & environment_override;
   begin
      return JT.USS (generic_system_command (command));
   exception
      when others =>
         return discerr;
   end get_environment;


   ---------------------------------
   --  get_options_configuration  --
   ---------------------------------
   function get_options_configuration (id : builders) return String
   is
      root    : constant String := get_root (id);
      command : constant String := chroot & root & environment_override &
        chroot_make_program & " -C " & dir_ports & "/" &
        get_catport (all_ports (trackers (id).seq_id));
   begin
      case software_framework is
         when ports_collection =>
            return JT.USS (generic_system_command (command & " showconfig"));
         when pkgsrc =>
            return JT.USS (generic_system_command (command & " show-options"));
      end case;
   exception
      when others =>
         return discerr;
   end get_options_configuration;


   ------------------------
   --  split_collection  --
   ------------------------
   function split_collection (line : JT.Text; title : String) return String
   is
      --  Support spaces in two ways
      --  1) quoted,  e.g. TYPING="The Quick Brown Fox"
      --  2) Escaped, e.g. TYPING=The\ Quick\ Brown\ Fox

      meat    : JT.Text;
      waiting : Boolean := True;
      escaped : Boolean := False;
      quoted  : Boolean := False;
      keepit  : Boolean;
      counter : Natural := 0;
      meatlen : Natural := 0;
      linelen : Natural := JT.SU.Length (line);
      onechar : String (1 .. 1);
      meatstr : String (1 .. linelen);
   begin
      loop
         counter := counter + 1;
         exit when counter > linelen;
         keepit  := True;
         onechar := JT.SU.Slice (Source => line,
                                 Low    => counter,
                                 High   => counter);

         if onechar (1) = LAT.Reverse_Solidus then
            --  A) if inside quotes, it's literal
            --  B) if it's first RS, don't keep but mark escaped
            --  C) If it's second RS, it's literal, remove escaped
            --  D) RS can never start a new NV pair
            if not quoted then
               if not escaped then
                  keepit := False;
               end if;
               escaped := not escaped;
            end if;
         elsif escaped then
            --  E) by definition, next character after an escape is literal
            --     We know it's not inside quotes. Keep this (could be a space)
            waiting := False;
            escaped := not escaped;
         elsif onechar (1) = LAT.Space then
            if waiting then
               keepit := False;
            else
               if not quoted then
                  --  name-pair ended, reset
                  waiting := True;
                  quoted  := False;
                  onechar (1) := LAT.LF;
               end if;
            end if;
         else
            waiting := False;
            if onechar (1) = LAT.Quotation then
               quoted := not quoted;
            end if;
         end if;
         if keepit then
            meatlen := meatlen + 1;
            meatstr (meatlen) := onechar (1);
         end if;
      end loop;
      return log_section (title, True) & LAT.LF &
        meatstr (1 .. meatlen) & LAT.LF &
        log_section (title, False) & LAT.LF;
   end split_collection;


   --------------------------
   --  get_port_variables  --
   --------------------------
   function get_port_variables (id : builders) return JT.Text
   is
      root    : constant String := get_root (id);
      command : constant String := chroot & root & environment_override &
        chroot_make_program & " -C " & dir_ports & "/" &
        get_catport (all_ports (trackers (id).seq_id));
      cmd_fpc : constant String := command &
        " -VCONFIGURE_ENV -VCONFIGURE_ARGS -VMAKE_ENV -VMAKE_ARGS" &
        " -VPLIST_SUB -VSUB_LIST";
      cmd_nps : constant String := command &
        " .MAKE.EXPAND_VARIABLES=yes -VCONFIGURE_ENV -VCONFIGURE_ARGS" &
        " -VMAKE_ENV -VMAKE_FLAGS -VBUILD_MAKE_FLAGS -VPLIST_SUBST" &
        " -VFILES_SUBST";
   begin
      case software_framework is
         when ports_collection =>
            return generic_system_command (cmd_fpc);
         when pkgsrc =>
            return generic_system_command (cmd_nps);
      end case;
   exception
      when others =>
         return JT.SUS (discerr);
   end get_port_variables;


   ---------------------------
   --  dump_port_variables  --
   ---------------------------
   procedure dump_port_variables (id : builders; content : JT.Text)
   is
      LA      : access TIO.File_Type := trackers (id).log_handle'Access;
      topline : JT.Text;
      concopy : JT.Text := content;
      type result_range_fpc is range 1 .. 6;
      type result_range_nps is range 1 .. 7;
   begin
      case software_framework is
         when ports_collection =>
            for k in result_range_fpc loop
               JT.nextline (lineblock => concopy, firstline => topline);
               case k is
               when 1 => TIO.Put_Line
                    (LA.all, split_collection (topline, "CONFIGURE_ENV"));
               when 2 => TIO.Put_Line
                    (LA.all, split_collection (topline, "CONFIGURE_ARGS"));
               when 3 => TIO.Put_Line
                    (LA.all, split_collection (topline, "MAKE_ENV"));
               when 4 => TIO.Put_Line
                    (LA.all, split_collection (topline, "MAKE_ARGS"));
               when 5 => TIO.Put_Line
                    (LA.all, split_collection (topline, "PLIST_SUB"));
               when 6 => TIO.Put_Line
                    (LA.all, split_collection (topline, "SUB_LIST"));
               end case;
            end loop;
         when pkgsrc =>
            for k in result_range_nps loop
               JT.nextline (lineblock => concopy, firstline => topline);
               case k is
               when 1 => TIO.Put_Line
                    (LA.all, split_collection (topline, "CONFIGURE_ENV"));
               when 2 => TIO.Put_Line
                    (LA.all, split_collection (topline, "CONFIGURE_ARGS"));
               when 3 => TIO.Put_Line
                    (LA.all, split_collection (topline, "MAKE_ENV"));
               when 4 => TIO.Put_Line
                    (LA.all, split_collection (topline, "MAKE_FLAGS"));
               when 5 => TIO.Put_Line
                    (LA.all, split_collection (topline, "BUILD_MAKE_FLAGS"));
               when 6 => TIO.Put_Line
                    (LA.all, split_collection (topline, "PLIST_SUBST"));
               when 7 => TIO.Put_Line
                    (LA.all, split_collection (topline, "FILES_SUBST"));
               end case;
            end loop;
      end case;
   end dump_port_variables;


   ----------------
   --  log_name  --
   ----------------
   function log_name (sid : port_id) return String
   is
      catport : constant String := get_catport (all_ports (sid));
   begin
      return JT.USS (PM.configuration.dir_logs) & "/" &
        JT.part_1 (catport) & "___" & JT.part_2 (catport) & ".log";
   end log_name;


   -----------------
   --  dump_file  --
   -----------------
   function  dump_file (filename : String) return String
   is
      File_Size : Natural := Natural (AD.Size (filename));

      subtype File_String    is String (1 .. File_Size);
      package File_String_IO is new Ada.Direct_IO (File_String);

      File     : File_String_IO.File_Type;
      Contents : File_String;
   begin
      File_String_IO.Open  (File, Mode => File_String_IO.In_File,
                            Name => filename);
      File_String_IO.Read  (File, Item => Contents);
      File_String_IO.Close (File);
      return String (Contents);
   end dump_file;


   ----------------------
   --  dump_make_conf  --
   ----------------------
   function dump_make_conf (id : builders; conf_file : String) return String
   is
      root     : constant String := get_root (id);
      filename : constant String := root & conf_file;
   begin
      return dump_file (filename);
   end dump_make_conf;


   ------------------
   --  initialize  --
   ------------------
   procedure initialize (test_mode : Boolean; jail_env : JT.Text) is
   begin
      set_uname_mrv;
      testing := test_mode;
      lock_localbase := testing and then Unix.env_variable_defined ("LOCK");
      slave_env := jail_env;
      declare
         logdir : constant String := JT.USS (PM.configuration.dir_logs);
      begin
         if not AD.Exists (logdir) then
            AD.Create_Path (New_Directory => logdir);
         end if;
      exception
         when error : others =>
            raise cycle_log_error
              with "failed to create " & logdir;
      end;
      obtain_custom_environment;
   end initialize;


   -------------------
   --  log_section  --
   -------------------
   function log_section (title : String; header : Boolean) return String
   is
      hyphens : constant String := (1 .. 50 => '-');
   begin
      if header then
         return LAT.LF & hyphens & LAT.LF & "--  " & title & LAT.LF & hyphens;
      else
         return "";
      end if;
   end log_section;


   ---------------------
   --  log_phase_end  --
   ---------------------
   procedure log_phase_end (id : builders)
   is
   begin
      TIO.Put_Line (trackers (id).log_handle, "" & LAT.LF);
   end log_phase_end;


   -----------------------
   --  log_phase_begin  --
   -----------------------
   procedure log_phase_begin (phase : String; id : builders)
   is
      hyphens : constant String := (1 .. 80 => '-');
      middle  : constant String := "--  Phase: " & phase;
   begin
      TIO.Put_Line (trackers (id).log_handle,
                    LAT.LF & hyphens & LAT.LF & middle & LAT.LF & hyphens);
   end log_phase_begin;


   -----------------------
   --  generic_execute  --
   -----------------------
   function generic_execute (id : builders; command : String;
                             dogbite : out Boolean;
                             time_limit : execution_limit) return Boolean
   is
      subtype time_cycle is execution_limit range 1 .. time_limit;
      subtype one_minute is Positive range 1 .. 230;  --  lose 10 in rounding
      type dim_watchdog is array (time_cycle) of Natural;
      use type Unix.process_exit;
      watchdog    : dim_watchdog;
      squirrel    : time_cycle := time_cycle'First;
      cycle_done  : Boolean := False;
      pid         : Unix.pid_t;
      status      : Unix.process_exit;
      lock_lines  : Natural;
      quartersec  : one_minute := one_minute'First;
      hangmonitor : constant Boolean := True;
      synthexec   : constant String := host_localbase & "/libexec/synthexec";
      truecommand : constant String := synthexec & " " &
                             log_name (trackers (id).seq_id) & " " & command;
   begin
      dogbite := False;
      watchdog (squirrel) := trackers (id).loglines;

      pid := Unix.launch_process (truecommand);
      if Unix.fork_failed (pid) then
         return False;
      end if;
      loop
         delay 0.25;
         if quartersec = one_minute'Last then
            quartersec := one_minute'First;
            --  increment squirrel
            if squirrel = time_cycle'Last then
               squirrel := time_cycle'First;
               cycle_done := True;
            else
               squirrel := squirrel + 1;
            end if;
            if hangmonitor then
               lock_lines := trackers (id).loglines;
               if cycle_done then
                  if watchdog (squirrel) = lock_lines then
                     --  Log hasn't advanced in a full cycle so bail out
                     dogbite := True;
                     Unix.kill_process_tree (process_group => pid);
                     delay 5.0;  --  Give some time for error to write to log
                     return False;
                  end if;
               end if;
               watchdog (squirrel) := lock_lines;
            end if;
         else
            quartersec := quartersec + 1;
         end if;
         status := Unix.process_status (pid);
         if status = Unix.exited_normally then
            return True;
         end if;
         if status = Unix.exited_with_error then
            return False;
         end if;
      end loop;
   end generic_execute;


   ------------------------------
   --  stack_linked_libraries  --
   ------------------------------
   procedure stack_linked_libraries (id : builders; base, filename : String)
   is
      command : String := chroot & base & " /usr/bin/objdump -p " & filename;
      comres  : JT.Text;
      topline : JT.Text;
      crlen1  : Natural;
      crlen2  : Natural;
   begin
      comres := generic_system_command (command);
      crlen1 := JT.SU.Length (comres);
      loop
         JT.nextline (lineblock => comres, firstline => topline);
         crlen2 := JT.SU.Length (comres);
         exit when crlen1 = crlen2;
         crlen1 := crlen2;
         if not JT.IsBlank (topline) then
            if JT.contains (topline, "NEEDED") then
               if not trackers (id).dynlink.Contains (topline) then
                  trackers (id).dynlink.Append (topline);
               end if;
            end if;
         end if;
      end loop;
   exception
         --  the command result was not zero, so it was an expected format
         --  or static file.  Just skip it.  (Should never happen)
      when bad_result : others => null;
   end stack_linked_libraries;


   ----------------------------
   --  log_linked_libraries  --
   ----------------------------
   procedure log_linked_libraries (id : builders)
   is
      procedure log_dump (cursor : string_crate.Cursor);

      comres  : JT.Text;
      topline : JT.Text;
      crlen1  : Natural;
      crlen2  : Natural;
      pkgfile : constant String := JT.USS
                         (all_ports (trackers (id).seq_id).package_name);
      pkgname : constant String := pkgfile (1 .. pkgfile'Last - 4);
      root    : constant String := get_root (id);
      command : constant String := chroot & root & environment_override &
        REP.root_localbase & "/sbin/pkg-static query %Fp " & pkgname;

      procedure log_dump (cursor : string_crate.Cursor) is
      begin
         TIO.Put_Line (trackers (id).log_handle,
                       JT.USS (string_crate.Element (Position => cursor)));
      end log_dump;
   begin
      TIO.Put_Line (trackers (id).log_handle,
                    "=> Checking shared library dependencies");

      comres := generic_system_command (command);
      crlen1 := JT.SU.Length (comres);
      loop
         JT.nextline (lineblock => comres, firstline => topline);
         crlen2 := JT.SU.Length (comres);
         exit when crlen1 = crlen2;
         crlen1 := crlen2;
         if REP.Platform.dynamically_linked (root, JT.USS (topline)) then
            stack_linked_libraries (id, root, JT.USS (topline));
         end if;
      end loop;
      trackers (id).dynlink.Iterate (log_dump'Access);
   exception
      when others => null;
   end log_linked_libraries;


   ----------------------------
   --  environment_override  --
   ----------------------------
   function environment_override (enable_tty : Boolean := False) return String
   is
      function set_terminal (enable_tty : Boolean) return String;
      function set_terminal (enable_tty : Boolean) return String is
      begin
         if enable_tty then
            return "TERM=cons25 ";
         end if;
         return "TERM=dumb ";
      end set_terminal;

      PATH : constant String := "PATH=/sbin:/bin:/usr/sbin:/usr/bin:"
        & REP.root_localbase & "/sbin:" & REP.root_localbase & "/bin ";

      TERM : constant String := set_terminal (enable_tty);
      USER : constant String := "USER=root ";
      HOME : constant String := "HOME=/root ";
      LANG : constant String := "LANG=C ";
      FTP  : constant String := "SSL_NO_VERIFY_PEER=1 ";
      PKG8 : constant String := "PORTSDIR=" & dir_ports & " " &
                                "PKG_DBDIR=/var/db/pkg8 " &
                                "PKG_CACHEDIR=/var/cache/pkg8 ";
      CENV : constant String := JT.USS (customenv);
      JENV : constant String := JT.USS (slave_env);
   begin
      return " /usr/bin/env -i " &
        USER & HOME & LANG & PKG8 & TERM & FTP & PATH & JENV & CENV;
   end environment_override;


   ---------------------
   --  set_log_lines  --
   ---------------------
   procedure set_log_lines (id : builders)
   is
      log_path : constant String := log_name (trackers (id).seq_id);
      command  : constant String := "/usr/bin/wc -l " & log_path;
      comres   : JT.Text;
   begin
      if not uselog then
         trackers (id).loglines := 0;
         return;
      end if;
      comres := JT.trim (generic_system_command (command));
      declare
         numtext : constant String :=
           JT.part_1 (S => JT.USS (comres), separator => " ");
      begin
         trackers (id).loglines := Natural'Value (numtext);
      end;
   exception
      when others => null;  -- just skip this cycle
   end set_log_lines;


   -----------------------
   --  format_loglines  --
   -----------------------
   function format_loglines (numlines : Natural) return String
   is
   begin
      if numlines < 10000000 then      --  10 million
         return JT.int2str (numlines);
      end if;
      declare
         kilo    : constant Natural := numlines / 1000;
         kilotxt : constant String  := JT.int2str (kilo);
      begin
         if numlines < 100000000 then      --  100 million
            return kilotxt (1 .. 2) & "." & kilotxt (3 .. 5) & 'M';
         elsif numlines < 1000000000 then  --  1 billion
            return kilotxt (1 .. 3) & "." & kilotxt (3 .. 4) & 'M';
         else
            return kilotxt (1 .. 4) & "." & kilotxt (3 .. 3) & 'M';
         end if;
      end;
   end format_loglines;


   ---------------------
   --  elapsed_build  --
   ---------------------
   function elapsed_build (id : builders) return String is
   begin
      return elapsed_HH_MM_SS (start => trackers (id).head_time,
                               stop => trackers (id).tail_time);
   end elapsed_build;


   -----------------------------
   --  get_packages_per_hour  --
   -----------------------------
   function get_packages_per_hour (packages_done : Natural;
                                   from_when : CAL.Time)
                                   return Natural
   is
      diff_days    : ACA.Day_Count;
      diff_secs    : Duration;
      leap_secs    : ACA.Leap_Seconds_Count;
      result       : Natural;
      rightnow     : CAL.Time := CAL.Clock;
      work_seconds : Integer;
      work_days    : Integer;
      use type ACA.Day_Count;
   begin
      if packages_done = 0 then
         return 0;
      end if;
      ACA.Difference (Left    => rightnow,
                      Right   => from_when,
                      Days    => diff_days,
                      Seconds => diff_secs,
                      Leap_Seconds => leap_secs);

      work_seconds := Integer (diff_secs);
      work_days    := Integer (diff_days);
      work_seconds := work_seconds + (work_days * 3600 * 24);

      if work_seconds < 0 then
         --  should be impossible to get here.
         return 0;
      end if;
      result := packages_done * 3600;
      result := result / work_seconds;
      return result;
   exception
      when others => return 0;
   end get_packages_per_hour;


   ------------------------
   --  mark_file_system  --
   ------------------------
   procedure mark_file_system (id : builders; action : String)
   is
      function attributes (action : String) return String;
      function attributes (action : String) return String
      is
         core : constant String := "uid,gid,mode,md5digest";
      begin
         if action = "preconfig" then
            return core & ",time";
         else
            return core;
         end if;
      end attributes;

      path_mm  : String := JT.USS (PM.configuration.dir_buildbase) & "/Base";
      path_sm  : String := JT.USS (PM.configuration.dir_buildbase) & "/SL" &
                           JT.zeropad (Natural (id), 2);
      mtfile   : constant String := path_mm & "/mtree." & action & ".exclude";
      command  : constant String := "/usr/sbin/mtree -X " & mtfile &
                          " -cn -k " & attributes (action) & " -p " & path_sm;
      filename : constant String := path_sm & "/tmp/mtree." & action;
      result   : JT.Text;
      resfile  : TIO.File_Type;
   begin
      result := generic_system_command (command);
      TIO.Create (File => resfile, Mode => TIO.Out_File, Name => filename);
      TIO.Put (resfile, JT.USS (result));
      TIO.Close (resfile);
   exception
      when others =>
         if TIO.Is_Open (resfile) then
            TIO.Close (resfile);
         end if;
   end mark_file_system;


   --------------------------------
   --  detect_leftovers_and_MIA  --
   --------------------------------
   function detect_leftovers_and_MIA (id : builders; action : String;
                                      description : String) return Boolean
   is
      package crate is new AC.Vectors (Index_Type   => Positive,
                                       Element_Type => JT.Text,
                                       "="          => JT.SU."=");
      package sorter is new crate.Generic_Sorting ("<" => JT.SU."<");
      function  ignore_modifications return Boolean;
      procedure print (cursor : crate.Cursor);
      procedure close_active_modifications;
      path_mm  : String := JT.USS (PM.configuration.dir_buildbase) & "/Base";
      path_sm  : String := JT.USS (PM.configuration.dir_buildbase) & "/SL" &
                           JT.zeropad (Natural (id), 2);
      mtfile   : constant String := path_mm & "/mtree." & action & ".exclude";
      filename : constant String := path_sm & "/tmp/mtree." & action;
      command  : constant String := "/usr/sbin/mtree -X " & mtfile & " -f " &
                                    filename & " -p " & path_sm;
      status    : Integer;
      comres    : JT.Text;
      topline   : JT.Text;
      crlen1    : Natural;
      crlen2    : Natural;
      toplen    : Natural;
      skiprest  : Boolean;
      passed    : Boolean := True;
      activemod : Boolean := False;
      modport   : JT.Text := JT.blank;
      reasons   : JT.Text := JT.blank;
      leftover  : crate.Vector;
      missing   : crate.Vector;
      changed   : crate.Vector;

      function ignore_modifications return Boolean
      is
         --  Some modifications need to be ignored
         --  A) */ls-R
         --     #ls-R files from texmf are often regenerated
         --  B) share/xml/catalog.ports
         --     # xmlcatmgr is constantly updating catalog.ports, ignore
         --  C) share/octave/octave_packages
         --     # Octave packages database, blank lines can be inserted
         --     # between pre-install and post-deinstall
         --  D) info/dir | */info/dir
         --  E) lib/gio/modules/giomodule.cache
         --     # gio modules cache could be modified for any gio modules
         --  F) etc/gconf/gconf.xml.defaults/%gconf-tree*.xml
         --     # gconftool-2 --makefile-uninstall-rule is unpredictable
         --  G) %%PEARDIR%%/.depdb | %%PEARDIR%%/.filemap
         --     # The is pear database cache
         --  H) "." with timestamp modification
         --     # this happens when ./tmp or ./var is used, which is legal
         filename : constant String := JT.USS (modport);
         fnlen    : constant Natural := filename'Length;
      begin
         if filename = "usr/local/share/xml/catalog.ports" or else
           filename = "usr/local/share/octave/octave_packages" or else
           filename = "usr/local/info/dir" or else
           filename = "usr/local/lib/gio/modules/giomodule.cache" or else
           filename = "usr/local/share/pear/.depdb" or else
           filename = "usr/local/share/pear/.filemap"
         then
            return True;
         end if;
         if filename = "." and then JT.equivalent (reasons, "modification") then
            return True;
         end if;
         if fnlen > 17 and then filename (1 .. 10) = "usr/local/"
         then
            if filename (fnlen - 4 .. fnlen) = "/ls-R" or else
              filename (fnlen - 8 .. fnlen) = "/info/dir"
            then
               return True;
            end if;
         end if;
         if fnlen > 56 and then filename (1 .. 39) =
           "usr/local/etc/gconf/gconf.xml.defaults/" and then
           filename (fnlen - 3 .. fnlen) = ".xml"
         then
            if JT.contains (filename, "/%gconf-tree") then
               return True;
            end if;
         end if;
         return False;
      end ignore_modifications;

      procedure close_active_modifications is
      begin
         if activemod and then not ignore_modifications then
            JT.SU.Append (modport, " [ ");
            JT.SU.Append (modport, reasons);
            JT.SU.Append (modport, " ]");
            if not changed.Contains (modport) then
               changed.Append (modport);
            end if;
         end if;
         activemod := False;
         reasons := JT.blank;
         modport := JT.blank;
      end close_active_modifications;

      procedure print (cursor : crate.Cursor)
      is
         dossier : constant String := JT.USS (crate.Element (cursor));
      begin
         TIO.Put_Line (trackers (id).log_handle, LAT.HT & dossier);
      end print;

   begin
      --  we can't use generic_system_command because exit code /= 0 normally
      comres := Unix.piped_command (command, status);
      crlen1 := JT.SU.Length (comres);
      loop
         skiprest := False;
         JT.nextline (lineblock => comres, firstline => topline);
         crlen2 := JT.SU.Length (comres);
         exit when crlen1 = crlen2;
         crlen1 := crlen2;
         toplen := JT.SU.Length (topline);
         if not skiprest and then JT.SU.Length (topline) > 6 then
            declare
               sx : constant Natural := toplen - 5;
               caboose  : constant String := JT.SU.Slice (topline, sx, toplen);
               filename : JT.Text := JT.SUS (JT.SU.Slice (topline, 1, sx - 1));
            begin
               if caboose = " extra" then
                  close_active_modifications;
                  if not leftover.Contains (filename) then
                     leftover.Append (filename);
                  end if;
                  skiprest := True;
               end if;
            end;
         end if;
         if not skiprest and then JT.SU.Length (topline) > 7 then
            declare
               canopy   : constant String := JT.SU.Slice (topline, 1, 7);
               filename : JT.Text := JT.SUS (JT.SU.Slice (topline, 8, toplen));
            begin
               if canopy = "extra: " then
                  close_active_modifications;
                  if not leftover.Contains (filename) then
                     leftover.Append (filename);
                  end if;
                  skiprest := True;
               end if;
            end;
         end if;
         if not skiprest and then JT.SU.Length (topline) > 10 then
            declare
               sx : constant Natural := toplen - 7;
               caboose  : constant String := JT.SU.Slice (topline, sx, toplen);
               filename : JT.Text := JT.SUS (JT.SU.Slice (topline, 3, sx - 1));
            begin
               if caboose = " missing" then
                  close_active_modifications;
                  if not missing.Contains (filename) then
                     missing.Append (filename);
                  end if;
                  skiprest := True;
               end if;
            end;
         end if;
         if not skiprest then
            declare
               line   : constant String := JT.USS (topline);
               blank8 : constant String := "        ";
               sx     : constant Natural := toplen - 7;
            begin
               if toplen > 5 and then line (1) = LAT.HT then
                  --  reason, but only valid if modification is active
                  if activemod then
                     if JT.IsBlank (reasons) then
                        reasons := JT.SUS (JT.part_1 (line (2 .. toplen), " "));
                     else
                        JT.SU.Append (reasons, " | ");
                        JT.SU.Append (reasons, JT.part_1
                                      (line (2 .. toplen), " "));
                     end if;
                  end if;
                  skiprest := True;
               end if;
               if not skiprest and then line (toplen) = LAT.Colon then
                  close_active_modifications;
                  activemod := True;
                  modport := JT.SUS (line (1 .. toplen - 1));
                  skiprest := True;
               end if;
               if not skiprest and then
                 JT.SU.Slice (topline, sx, toplen) = " changed"
               then
                  close_active_modifications;
                  activemod := True;
                  modport := JT.SUS (line (1 .. toplen - 8));
                  skiprest := True;
               end if;
            end;
         end if;
      end loop;
      close_active_modifications;
      sorter.Sort (Container => changed);
      sorter.Sort (Container => missing);
      sorter.Sort (Container => leftover);

      TIO.Put_Line (trackers (id).log_handle, LAT.LF & "=> Checking for " &
                      "system changes " & description);
      if not leftover.Is_Empty then
         passed := False;
         TIO.Put_Line (trackers (id).log_handle, LAT.LF &
                      "   Left over files/directories:");
         leftover.Iterate (Process => print'Access);
      end if;
      if not missing.Is_Empty then
         passed := False;
         TIO.Put_Line (trackers (id).log_handle, LAT.LF &
                       "   Missing files/directories:");
         missing.Iterate (Process => print'Access);
      end if;
      if not changed.Is_Empty then
         passed := False;
         TIO.Put_Line (trackers (id).log_handle, LAT.LF &
                       "   Modified files/directories:");
         changed.Iterate (Process => print'Access);
      end if;
      if passed then
         TIO.Put_Line (trackers (id).log_handle, "Everything is fine.");
      end if;
      return passed;
   end detect_leftovers_and_MIA;


   -----------------------------
   --  interact_with_builder  --
   -----------------------------
   procedure interact_with_builder (id : builders)
   is
      root      : constant String := get_root (id);
      command   : constant String := chroot & root &
                  environment_override (enable_tty => True) &
                  REP.Platform.interactive_shell;
      result    : Boolean;
   begin
      TIO.Put_Line ("Entering interactive test mode at the builder root " &
                      "directory.");
      TIO.Put_Line ("Type 'exit' when done exploring.");
      result := Unix.external_command (command);
   end interact_with_builder;


   ---------------------------------
   --  obtain_custom_environment  --
   ---------------------------------
   procedure obtain_custom_environment
   is
      target_name : constant String := PM.synth_confdir & "/" &
                    JT.USS (PM.configuration.profile) & "-environment";
      fragment : TIO.File_Type;
   begin
      customenv := JT.blank;
      if AD.Exists (target_name) then
         TIO.Open (File => fragment, Mode => TIO.In_File, Name => target_name);
         while not TIO.End_Of_File (fragment) loop
            declare
               Line : String := TIO.Get_Line (fragment);
            begin
               if JT.contains (Line, "=") then
                  JT.SU.Append (customenv, JT.trim (Line) & " ");
               end if;
            end;
         end loop;
         TIO.Close (fragment);
      end if;
   exception
      when others =>
         if TIO.Is_Open (fragment) then
            TIO.Close (fragment);
         end if;
   end obtain_custom_environment;


   --------------------------------
   --  set_localbase_protection  --
   --------------------------------
   procedure set_localbase_protection (id : builders; lock : Boolean)
   is
      procedure remount (readonly : Boolean);
      procedure dismount;

      smount        : constant String := get_root (id);
      slave_local   : constant String := smount & "_localbase";


      procedure remount (readonly : Boolean)
      is
         cmd_freebsd   : String := "/sbin/mount_nullfs ";
         cmd_dragonfly : String := "/sbin/mount_null ";
         points        : String := slave_local & " " & smount & REP.root_localbase;
         options       : String := "-o ro ";
         cmd           : JT.Text;
         cmd_output    : JT.Text;
      begin
         if JT.equivalent (PM.configuration.operating_sys, "FreeBSD") then
            cmd := JT.SUS (cmd_freebsd);
         else
            cmd := JT.SUS (cmd_dragonfly);
         end if;
         if readonly then
            JT.SU.Append (cmd, options);
         end if;
         JT.SU.Append (cmd, points);

         if not Unix.piped_mute_command (JT.USS (cmd), cmd_output) then
            if uselog then
               TIO.Put_Line (trackers (id).log_handle,
                             "command failed: " & JT.USS (cmd));
               if not JT.IsBlank (cmd_output) then
                  TIO.Put_Line (trackers (id).log_handle, JT.USS (cmd_output));
               end if;
            end if;
         end if;
      end remount;

      procedure dismount
      is
         cmd_unmount : constant String := "/sbin/umount " & smount & REP.root_localbase;
         cmd_output  : JT.Text;
      begin
         if not Unix.piped_mute_command (cmd_unmount, cmd_output) then
            if uselog then
               TIO.Put_Line (trackers (id).log_handle,
                             "command failed: " & cmd_unmount);
               if not JT.IsBlank (cmd_output) then
                  TIO.Put_Line (trackers (id).log_handle, JT.USS (cmd_output));
               end if;
            end if;
         end if;
      end dismount;

   begin
      if lock then
         dismount;
         remount (readonly => True);
      else
         dismount;
         remount (readonly => False);
      end if;
   end set_localbase_protection;


   ------------------------------
   --  timeout_multiplier_x10  --
   ------------------------------
   function timeout_multiplier_x10 return Positive
   is
      average5 : constant Float := REP.Platform.get_5_minute_load;
      avefloat : constant Float := average5 / Float (number_cores);
   begin
      if avefloat <= 1.0 then
         return 10;
      else
         return Integer (avefloat * 10.0);
      end if;
   exception
      when others => return 10;
   end timeout_multiplier_x10;


   ---------------------------
   --  valid_test_phase #2  --
   ---------------------------
   function valid_test_phase (afterphase : String) return Boolean is
   begin
      if afterphase = "extract" or else
        afterphase = "patch" or else
        afterphase = "configure" or else
        afterphase = "build" or else
        afterphase = "stage" or else
        afterphase = "install" or else
        afterphase = "deinstall"
      then
         return True;
      else
         return False;
      end if;
   end valid_test_phase;


   ---------------------------
   --  builder_status_core  --
   ---------------------------
   function builder_status_core (id       : builders;
                                 shutdown : Boolean := False;
                                 idle     : Boolean := False;
                                 phasestr : String)
                                 return Display.builder_rec
   is
      result   : Display.builder_rec;
      phaselen : constant Positive := phasestr'Length;
   begin
      --  123456789 123456789 123456789 123456789 1234
      --   SL  elapsed   phase              lines  origin
      --   01  00:00:00  extract-depends  9999999  www/joe

      result.id       := id;
      result.slavid   := JT.zeropad (Natural (id), 2);
      result.LLines   := (others => ' ');
      result.phase    := (others => ' ');
      result.origin   := (others => ' ');
      result.shutdown := False;
      result.idle     := False;

      if shutdown then
         --  Overrides "idle" if both Shutdown and Idle are True
         result.Elapsed  := "Shutdown";
         result.shutdown := True;
         return result;
      end if;
      if idle then
         result.Elapsed := "Idle    ";
         result.idle    := True;
         return result;
      end if;

      declare
         catport  : constant String :=
           get_catport (all_ports (trackers (id).seq_id));
         numlines : constant String := format_loglines (trackers (id).loglines);
         linehead : constant Natural := 8 - numlines'Length;
      begin
         result.Elapsed := elapsed_HH_MM_SS (start => trackers (id).head_time,
                                             stop  => CAL.Clock);
         result.LLines (linehead .. 7) := numlines;
         if phaselen <= result.phase'Length then
            result.phase  (1 .. phasestr'Length) := phasestr;
         else
            --  special handling for long descriptions
            if phasestr = "bootstrap-depends" then
               result.phase (1 .. 14) := "bootstrap-deps";
            else
               result.phase :=  phasestr
                 (phasestr'First .. phasestr'First + result.phase'Length - 1);
            end if;
         end if;

         if catport'Length > 37 then
            result.origin (1 .. 36) := catport (1 .. 36);
            result.origin (37) := LAT.Asterisk;
         else
            result.origin (1 .. catport'Length) := catport;
         end if;
      end;
      return result;
   end builder_status_core;

end PortScan.Buildcycle;
