CREATE SCHEMA IF NOT EXISTS EXA_TOOLBOX;
open schema EXA_TOOLBOX;
--
-- Example of valid LDAP connection
--
--create or replace connection test_ldap_server to 'ldap://192.168.1.155:389' user 'cn=admin,dc=manhlab,dc=com' identified by 'abc';
--/
--====================================
CREATE OR REPLACE LUA SCRIPT "SYNC_AD_GROUPS_TO_DB_ROLES_AND_USERS" (LDAP_CONNECTION, GROUP_ATTRIBUTE, USER_ATTRIBUTE, EXECUTION_MODE, OPT_SEND_EMAIL, OPT_WRITE_AUDIT) RETURNS TABLE AS
--====================================
/*--------------------------------------
-- NOTES for Usage
---------------------------------------
-- GROUP ATTRIBUTE refers to the attribute to search in the group for all of the members. Default is 'member'
-- USER ATTRIBUTE refers to the attribute of the user which contains the username. Default is uid
-- EXECUTION_MODE options: DEBUG or EXECUTE. In debug mode, all queries are rolled back

--------------------------------------
---------  General READ ME  ----------
--------------------------------------
Purpose: This script is designed to manage the database users and roles using 
         LDAP for authentication and creating/removing the database users.

About:   There have been enhancements added to this script, 
         but these enhancements are turned off by default so you can run this 
         as-is (core faunctionality) without the enhancements.

Enhancement 1: Arguement: OPT_SEND_EMAIL -- > disbled by default
               Option to capture and send LDAP changes through email. 
               ** Requires a Python UDF MAIL_MAN.py to receive
               the LDAP changes and email them. There is a
               check in this script to first ensure there
               is a script named 'MAIL_MAN' before trying
               to call it.
               
Enhancement 2: Arguement: OPT_WRITE_AUDIT --> disabled by default
               Option to create/write LDAP changes to reporting table.
               The table is named: LDAP_REPORT_TBL and is 
               created under the same schema as this script's schema.
               
Enhancement 3: In the returned record set displayed, add a new message
               if the EXAOperation "LDAP Server URL" parameter is NOT set, as 
               this will impact LDAP functionality. Once the "LDAP Server URL"
               parameter is set in EXAOperation, then there is
               no addition message. It would be annoying seeing the
               "LDAP" parameter contents displayed each time this
               script executes.
               
Enhancement 4: Display in the returned record set a 1 line message
               if the EXAOperation UI does not have the "LDAP Server URL"
               parameter set up. 
         
Enhancement 5: Scripts GET_AD_ATTRIBUTE & LDAP_HELPER are now Python3

Enhancement 6: Continue processing despite having an Exasol role that 
               is not defined AD (LDAP) group entry. (Bogus entry)
               
Enhancement 7: Remove hardcoding of CONNECTION name when calling GET_AD_ATTRIBUTES.
               Having the hardcoded CONNECTION, meant results were returned
               when the CONNECTION defined in the EXECUTE SCRIPT was invalid.

--------------------------------------
--------- Where to begin?   ----------
--------------------------------------
About:  These are suggestions to ease implementation of the LDAP Sync process.

1) At the top of each script/udf is "open schema xxxxx". Set the schema in this script,
   GET_AD_ATTRIBUTES and LDAP_HELPER. The default is to create and use the schema "EXA_TOOLBOX".
   Your use case will determine the appropriate schema. This is important, as we have 
   remove the hardcoded schemas in each of the scripts provided, as they previously were using 
   the default schema "EXA_TOOLBOX".
   
2) Information to compile:
   a) DSN Name and I.P. address of the LDAP Server, including the port. Upon initial 
      implementation, we suggest using the unsecured LDAP port. Later, you can make
      changes to implement the secured LDAP configurations.
   b) An LDAP user, and password, which has permissions to query the LDAP Server.
   c) A valid LDAP Distinguished Name record, for either a user or a group. This will be used 
     when confirming the LDAP connection and running "LDAP_HELPER" with
     the LDAP query criteria. Example for LDAP user query which "LDAP_HELPER"
     can use:
         'cn=John Doe,ou=Users,dc=example,dc=com', 'uid'

3) Ensure Exasol's EXAOperation UI has the DNS servers filled in, along with the "LDAP Server URLs"
   filled in. "DNS Server 1" (and 2) can be found on the "Network" side menu. "LDAP Server URLs"
   is visible when click on the EXASolution page, and then click on the entry under "DB Name". From 
   there, choose the "EDIT" button and then look for the "LDAP Server URLS". Exasol is configured
   to only work with 1 LDAP Server, so adding a range of servers is pointless. 
   
   ** Note: Setting the "DNS Server 1" (and 2) can be done ad-hoc, without having to
   restart the database. Setting the "LDAP Server URLS" requires you to first
   shutdown the database, choose "Edit" (see the previous paragraph), setting the
   "LDAP Server URLS", saving your changes and starting the database.
   
4) To ease implementing LDAP functionality, use the I.P. address of your LDAP Server
   when setting the EXASolution "LDAP Server URLS" and creating the LDAP Connection object
   for this script. Examples:
       "LDAP Server URLS" --> "ldap://192.168.1.155:389"
       "CREATE CONNECTION "test_ldap_server" to 'ldap://192.168.1.155:389....'
   The reasoning is to eliminate failed connections using the DNS name of the 
   LDAP Server. Out of the box, Exasol does not know of your DNS or LDAP Servers,
   and some forget to set the "DNS Server 1" (and 2) on the Network page. 
   
5) First implement the unsecured LDAP functionality, (using http prefix "ldap://" 
   ensuring the proper results, then plan to implement the secured LDAP setup. 
   It's much easier to implement in smaller tasks, than to try an implement the ideal setup all at once.
   
6) Compile this script, and "GET_AD_ATTRIBUTES" incorporating the information you compiled. 
   This will ensure core functionality is implemented. To assist with verifying LDAP connections
   and general troubleshooting, compile "LDAP_HELPER" using the information you compiled. Specifically,
   build your CONNECTION using the "CREATE CONNECTION" SQL command and set up the SQL to call
   "LDAP_HELPER" with the LDAP distinguished name entry. Examples:
       a) Build Connection:
           create or replace connection test_ldap_server to 'ldap://192.168.1.155:389' user 'cn=admin,dc=example,dc=com' identified by 'secret';
       b) Build the SQL to call "LDAP_HELPER":
           select <your_schema>.LDAP_HELPER_('TEST_LDAP_SERVER', 'cn=John Doe,ou=Users,dc=example,dc=com') ;
   
y) On a closing note, when you first test the newly implemented functionality, this script will timeout
   after 30 seconds, if a valid connection is not made. Should this happen, these are the
   most likely culprits:
   a) The LDAP I.P. address and Port are incorrect.
   b) You configured your CONNECTION using the LDAP DNS server name and missed setting
      the EXASolution UI entries "DNS Server 1". You can rebuild your CONNECTION using
      the LDAP Server I.P address and retry.
   c) There is a firewall between Exasol and the LDAP server. You can also use
      this link to build just a connection tester:
      https://github.com/exasol/exa-toolbox/blob/master/utilities/check_connectivity.sql
      if you are sure the LDAP I.P. address is correct, then maybe the port is wrong.
      Try running the "check_connectivity" SQL using a different port, such as 80.
      Here are some common well known port numbers:
            21: FTP Server.
            22: SSH Server (remote login)
            25: SMTP (mail server)
            53: Domain Name System (Bind 9 server)
            80: World Wide Web (HTTPD server)
            110: POP3 mail server.
            143: IMAP mail server.
            443: HTTP over Transport Layer Security/Secure Sockets Layer (HTTPDS server)

** The motivation for this change comes from https://www.exasol.com/support/browse/SUPPORT-27162
--------------------------------------
------  Internal CX reference --------
--------------------------------------
https://www.exasol.com/support/browse/SUPPORT-13212 --> LDAP Server URLs not set
https://www.exasol.com/support/browse/SUPPORT-17604 --> DNS not defined (LDAP was DNS)
https://www.exasol.com/support/browse/SUPPORT-15274 --> Show where lDAP bind is failing
https://www.exasol.com/support/browse/SUPPORT-12297 --> Network timeouts
https://www.exasol.com/support/browse/SUPPORT-11854 --> Sporadic Auth failure (not obvious to customer)
https://www.exasol.com/support/browse/SUPPORT-10716 --> Plea for improved LDAP error reporting (Auth failures)
https://www.exasol.com/support/browse/SUPPORT-7652  --> Customer needed call just to test LDAP connection
https://www.exasol.com/support/browse/SUPPORT-25276 --> Can we send emails thru script?
https://www.exasol.com/support/browse/SUPPORT-9610  --> Steps to add LDAP Server URLs (is now part of this script's comments


*/
--###################################
-- FUNCTIONS (Enhancements)
--###################################
---------------------------------------
function audit_log() 
---------------------------------------
--
-- This function only gets executed if parameter "OPT_WRITE_AUDIT" is set to 'ON'.
--
    local user = exa.meta.current_user
    local session = exa.meta.session_id
    local schema  = exa.meta.current_schema
    local script  = exa.meta.script_name
    local start_time = os.date('%Y-%m-%d %H:%M:%S')
    ------------------------------
    -- If Debug and EXAOperation does not set the "LDAP Server URL" parameter filled out, 
    --   then don't write the first record to the LDAP_REPORT_TBL, 
    --   as it was only informational and not pertinent to LDAP changes. Do display "LDAP Server URL" 
    --   is not set message in the returned record output. 
    --       If "DEBUG MODE ON" and OPT_WRITE_AUDIT parameter is 'ON',then writing to the LDAP_REPORT_TBL
    --   will populate the column "MODE" with "DEBUG". This allows querying LDAP_REPORT_TBL 
    --   for "DEBUG" or "EXECUTE".
    ------------------------------
    if (debug) then
        ------------------------------
        -- This "if" asks if the EXAOperation LDAP parameter is set.
        -- If it's not set, then the returned results includes a 
        -- message stating EXAOperation's "LDAP Server URL" is NOT set". We do NOT
        -- write this LDAP message to the LDAP_RESULT_TBL.
        ------------------------------
        if (res_meta[1][1] == null) then 
            for i=2,#summary do
               local suc1, res1 = pquery([[INSERT INTO "LDAP_REPORT_TBL" values(:o,:ses,:order, :uzr,:sch, :scr, :mo, :s, :suc, :err)]],{o=start_time, ses=session, order = i-1, uzr=user, sch=schema, scr=script, mo=string.upper(EXECUTION_MODE), s=summary[i][1], suc=summary[i][2], err=summary[i][3]})
               if not suc1 then
                   output(res1.error_message)
               end -- END if
            end -- END for
        else
        ------------------------------
        -- If the EXAOperation "LDAP: parameter is set, there is no message
        -- to skip when writing to the LDAP_REPORT_TBL
        ------------------------------
           for i=1,#summary do
               local suc1, res1 = pquery([[INSERT INTO "LDAP_REPORT_TBL" values(:o,:ses,:order, :uzr,:sch, :scr, :mo, :s, :suc, :err)]],{o=start_time, ses=session, order = i, uzr=user, sch=schema, scr=script, mo=string.upper(EXECUTION_MODE), s=summary[i][1], suc=summary[i][2], err=summary[i][3]})
               if not suc1 then
                   output(res1.error_message)
               end -- END if
            end -- END for      
        end --END if res_meta
    else
        ------------------------------
        -- This is the ELSE that writes the actual changes,
        -- that is, the parameter "EXECUTION_MODE" is set to "EXECUTE".
        ------------------------------
        for i=1,#summary do
           local suc1, res1 = pquery([[INSERT INTO "LDAP_REPORT_TBL" values(:o,:ses,:order, :uzr,:sch, :scr, :mo, :s, :suc, :err)]],{o=start_time, ses=session, order = i, uzr=user, sch=schema, scr=script, mo=string.upper(EXECUTION_MODE), s=summary[i][1],  suc=summary[i][2], err=summary[i][3]})
           if not suc1 then
               output(res1.error_message)
           end -- END if
        end -- END for loop
    end -- END if (debug)
end --END Function

---------------------------------------
function email_ldap(summary) 
---------------------------------------
--
-- This function only gets executed if parameter "OPT_SEND_MAIL" is set to 'ON'.
--
    local s = {}
    for i=1,#summary do
        s[#s+1] = "'"
        s[#s+1] = summary[i][1]
        s[#s+1] = "'"
    end
    s = table.concat(s)
    -- output(s) --Uncomment to see output (providing the EXECUTE SCRIPT SQL command
    --      has the "OUTPUT" option)

    local schema  = exa.meta.current_schema
    --
    -- Search for script MAIL_MAN in the database
    --
    suc_sch, res_sch = pquery([[SELECT COUNT(*) FROM EXA_DBA_SCRIPTS WHERE SCRIPT_SCHEMA = :scm and SCRIPT_NAME = 'MAIL_MAN']],{scm=schema})
    
    --
    -- If MAIL_MAN is found, then continue, else OUTPUT the script is not in the database
    --     This prevents accidental error of calling a non-existent script
    --
    if suc_sch then
        if res_sch[1][1] == 1 then
            --
            -- MAIL_MAN script found in database, so "make the call to MAIL_MAN"
            --
            sucy, resy = pquery([[select MAIL_MAN(:str)]], {str=s})
            if sucy ~= true then
                 output(resy.error_message)
            end -- END if stmt
        else
            output("Send email not executed. Could not find script = MAIL_MAN under schema "..schema)
        end -- END res_sch
    else
        output("Send email not executed. Could not find script = MAIL_MAN under schema "..schema)
    end -- END suc_sch
end

--###################################
-- BEGIN MAIN LOGIC
--###################################
-------------------------------------
-- Enhancement
-------------------------------------
if OPT_WRITE_AUDIT == 'ON' or string.upper(EXECUTION_MODE) == 'EXECUTE' then 
    query([[CREATE TABLE IF NOT EXISTS LDAP_REPORT_TBL(START_TIME Timestamp, SESSION_ID CHAR(19), REC_NO INTEGER, USER_ID VARCHAR(200), SCHEMA_NAME VARCHAR(200), SCRIPT_NAME VARCHAR(200), MODE CHAR(7), QUERY VARCHAR(1000), SUCCESS BOOLEAN, ERROR VARCHAR(1000))]])
    query([[commit]])  
end
-------------------------------------
-- End of enhancement
-------------------------------------

if GROUP_ATTRIBUTE == NULL then
        GROUP_ATTRIBUTE = 'member'
end

if USER_ATTRIBUTE == NULL then
        USER_ATTRIBUTE = 'uid'
end

if EXECUTION_MODE == NULL then
        debug = false
elseif string.upper(EXECUTION_MODE) == 'EXECUTE' then
        debug = false
elseif string.upper(EXECUTION_MODE) == 'DEBUG' then
        debug = true
else
        error([[Invalid entry for EXECUTION_MODE. Please use 'DEBUG' or 'EXECUTE']])
end


dcl = query([[

WITH 
---------------------------------------
get_ad_group_members AS (
---------------------------------------
/* This CTE will get the list of members in LDAP for each role that contains a comment */

		/*snapshot execution*/ SELECT  
		EXA_TOOLBOX.GET_AD_ATTRIBUTE(:l, ROLE_COMMENT, 'uniqueMember',:em)
		FROM
		select * from EXA_DBA_ROLES
		where ROLE_NAME NOT IN ('PUBLIC','DBA') AND UPPER(ROLE_COMMENT) LIKE '%DC=%'
		--exclude default EXASOL groups, all other roles MUST be mapped to AD/LDAP groups
		--the mapping to a LDAP role is done via a COMMENT 
	)
---------------------------------------
, exa_membership as (
---------------------------------------
/* This CTE gets the list of users who are members of roles from Exasol. This is used to compare the groups between LDAP and EXA */

        /*snapshot execution*/ SELECT R.ROLE_COMMENT, U.DISTINGUISHED_NAME, P.GRANTED_ROLE, P.GRANTEE FROM EXA_DBA_ROLE_PRIVS P
                JOIN EXA_DBA_ROLES R ON R.ROLE_NAME = P.GRANTED_ROLE
                JOIN EXA_DBA_USERS U ON U.USER_NAME = P.GRANTEE
                WHERE UPPER(R.ROLE_COMMENT) LIKE '%DC=%'
                AND UPPER(U.DISTINGUISHED_NAME) LIKE '%DC=%'
                AND GRANTED_ROLE NOT IN ('PUBLIC')
        )
---------------------------------------
, alter_users as (
---------------------------------------
/* This CTE will find all users who do not have a DISTINGUISHED_NAME configured in Exasol, but DOES have a matching username.
   In these cases, the script will ALTER the user and change the distinguished name instead of re-creating the user */

        /*snapshot execution*/ SELECT 'ALTER USER "' || upper(VAL) || '" IDENTIFIED AT LDAP AS ''' || SEARCH_STRING || ''';' AS DCL_STATEMENT, 1 ORDER_ID, UPPER(val) VAL, search_string
        FROM (
                select EXA_TOOLBOX.GET_AD_ATTRIBUTE(:l, VAL, 'uid', :em) from
			(
				select distinct VAL
				from	
				get_ad_group_members 
				WHERE 
				VAL NOT IN 
				(
					SELECT distinct  DISTINGUISHED_NAME 
					FROM
		 			EXA_DBA_USERS
				)
				and VAL NOT like '%No such object%'
			)  --get uid attribute as USER_NAME in database
		
		) WHERE upper(VAL) IN (SELECT DISTINCT USER_NAME FROM EXA_DBA_USERS))
---------------------------------------
, drop_users AS (
---------------------------------------
/* This CTE will find all users who are no longer a part of any LDAP group and will drop them
    NOTE: If the user is the owner of any database objects, the DROP will fail and an appropriate error message is displayed in the script output
    If you want to drop users who are owners, you can amend the query and replace '"; --' with '" CASCADE; -- */
    
		/*snapshot execution*/ select
		'DROP USER "' || UPPER(USER_NAME) || '"; --' || DISTINGUISHED_NAME  AS DCL_STATEMENT, 5 ORDER_ID
		from
		EXA_DBA_USERS
		WHERE UPPER(DISTINGUISHED_NAME) LIKE '%DC=%'
		AND
		DISTINGUISHED_NAME NOT IN 
		(
			SELECT distinct VAL
			FROM
 			get_ad_group_members 
		)
		AND UPPER(USER_NAME) NOT IN (SELECT VAL FROM ALTER_USERS)
	)
---------------------------------------
, create_users AS (
---------------------------------------
/* This CTE will create users who are found to be in an LDAP group, but the distinguished name is not found in Exasol
    Users who are altered are ignored and not created again */
    
		/*snapshot execution*/ select
		'CREATE USER "' ||  UPPER(VAL)  || '"  IDENTIFIED AT LDAP AS ''' || SEARCH_STRING ||''';'  AS DCL_STATEMENT,2 ORDER_ID
		from

		(
			select EXA_TOOLBOX.GET_AD_ATTRIBUTE(:l, VAL, 'uid', :em) from
			(
				select distinct VAL
				from	
				get_ad_group_members 
				WHERE 
				VAL NOT IN 
				(
					SELECT distinct  DISTINGUISHED_NAME 
					FROM
		 			EXA_DBA_USERS
				) and VAL NOT like '%No such object%'
			)  --get uid attribute as USER_NAME in database
		
		)
		where UPPER(VAL) NOT IN (SELECT VAL FROM ALTER_USERS)

	)
---------------------------------------
,revokes AS (
---------------------------------------
/* This CTE will only revoke roles from users if they are a part a member of the role in EXA, but are no longer in the group in LDAP */

		SELECT 'REVOKE "' || GRANTED_ROLE || '" FROM "' || UPPER(GRANTEE) || '";' AS DCL_STATEMENT, 3 ORDER_ID from exa_membership e
                full outer join get_ad_group_members a on e.role_comment = a.search_string and e.distinguished_name = a.val
                where search_string is null
	)
---------------------------------------
,all_user_names(DISTINGUISHED_NAME, VAL, USER_NAME)  as (
---------------------------------------
/* This CTE will get the "user name" attribute for LDAP. The exact attribute may vary */
	
	select EXA_TOOLBOX.GET_AD_ATTRIBUTE(:l, VAL, 'uid', :em) from
	(
		select distinct VAL
		from	
		get_ad_group_members
		WHERE VAL NOT like '%No such object%'
	)

)
---------------------------------------
, grants AS (
---------------------------------------
/* This CTE will grant roles to users when it sees an LDAP user who is a role member, but the equivalent database user is not granted the role */
        
        /*snapshot execution*/ SELECT 'GRANT "' || R.ROLE_NAME ||'" TO "' || UPPER(U.USER_NAME) || '";' AS DCL_STATEMENT, 4 ORDER_ID FROM EXA_MEMBERSHIP e
		FULL OUTER JOIN get_ad_group_members a on e.role_comment = a.search_string and e.distinguished_name = a.val
		full outer join 
		      (SELECT ROLE_NAME, ROLE_COMMENT FROM EXA_DBA_ROLES where ROLE_NAME NOT IN ('PUBLIC','DBA') AND UPPER(ROLE_COMMENT) LIKE '%DC=%') r
		      on r.role_comment = a.search_string 
		JOIN ALL_USER_NAMES u on u.distinguished_name = a.val
		where e.role_comment is null
		and  u.USER_NAME NOT like '%No such object%'
		
	)

select DCL_STATEMENT, ORDER_ID from alter_users

union all

select * from  create_users

union all

select * from revokes

union all

select * from grants

union all

select * from drop_users

order by ORDER_ID ;

]], {l=LDAP_CONNECTION, u=USER_ATTRIBUTE, g=GROUP_ATTRIBUTE,em=EXECUTION_MODE})

---------------------------------------
-- Debug information showing the EXAOperation UI parameter "LDAP Server URL" address.
---------------------------------------
suc_meta, res_meta = pquery([[select Param_value from EXA_COMMANDLINE   where upper(Param_name) = :ln]], {ln='LDAPSERVER'})

summary = {}

if (debug) then
-- in debug mode, all queries are performed to see what an error message may be, but are then rolled back so no changes are committed.
       ----------------------------------------
       --Notify user if EXAOperation missing LDAP connection
       ----------------------------------------
        if (suc_meta) then
            if (res_meta[1][1] == null) then
                summary[#summary+1] = {'--WARNING! EXASolution (EXAOperation) "LDAP Server URLs" parameter is NOT set. Exasol can not auth using LDAP', null,null}
            end -- End if (res_meta...
        end -- End If suc_meta
        
        ----------------------------------------
        -- Start the LDAP messages stating DEBUG
        ----------------------------------------
        
        summary[#summary+1] = {"DEBUG MODE ON - ALL QUERIES ROLLED BACK",null,null}
        
        for i=1,#dcl do
                my_DCL_STATEMENT = string.gsub( dcl[i].DCL_STATEMENT, "(CREATE USER.+%a)(')(%a)", "%1%2%2%3", 1)
                --output(my_DCL_STATEMENT)
                suc,res = pquery(my_DCL_STATEMENT)
                            
                if (suc) then
                -- query was successful
                        summary[#summary+1] = {my_DCL_STATEMENT,'TRUE',NULL}
                else
                -- query returned an error message, display the error in the script output
                        summary[#summary+1] = {my_DCL_STATEMENT,'FALSE',res.error_message}
                end
        end 
        query([[ROLLBACK]])
else
-- Not debug mode, queries can be committed on script completion
        for i=1,#dcl do
            my_DCL_STATEMENT = string.gsub( dcl[i].DCL_STATEMENT, "(CREATE USER.+%a)(')(%a)", "%1%2%2%3", 1)
                suc,res = pquery(my_DCL_STATEMENT)
                
                if (suc) then
                --query was successful
                        summary[#summary+1] = {my_DCL_STATEMENT,'TRUE',NULL}
                else
                --query returned an error message, display the error in the script output
                        summary[#summary+1] = {my_DCL_STATEMENT,'FALSE',res.error_message}
                end  
        end
end


---------------------------------------
-- Enhancement
---------------------------------------
if OPT_SEND_EMAIL == 'ON' then
    email_ldap(summary)
end

-------------------------------------
-- Enhancement 
-------------------------------------
if OPT_WRITE_AUDIT == 'ON' or string.upper(EXECUTION_MODE) == 'EXECUTE' then
    audit_log()
end

return summary, ("QUERY_TEXT VARCHAR(200000),SUCCESS BOOLEAN, ERROR_MESSAGE VARCHAR(20000)")
/
/*
---------------------------------------
--Main SYNC Script Example. (Don't forget to "open" the schema, first)
---------------------------------------
--
--EXECUTE SCRIPT "SYNC_AD_GROUPS_TO_DB_ROLES_AND_USERS"('TEST_LDAP_WEB','uniqueMember','uid','DEBUG','OFF', 'OFF'); -- with output;
--