open schema retail;
/*=======================================================
Next 4 lines are tesing only, Please delete!
  =======================================================*/
GRANT CREATE SESSION TO "AM";
GRANT CREATE SESSION TO "EU";
GRANT CREATE SESSION TO "LDAP_DBA";
GRANT CREATE SESSION TO "JASKEW";

select current_session;

/*=======================================================*/
create or replace LUA script attempt() as
/*=======================================================*/
    local user = exa.meta.current_user
    local session = exa.meta.session_id
    local schema  = exa.meta.current_schema
    local script  = exa.meta.script_name
    local start_time = os.date('%Y-%m-%d %H:%M:%S')
 /*------------------------------------------------------
    Create recovery table to restore GRANTS
   ------------------------------------------------------*/
    
    query([[
          CREATE TABLE IF NOT EXISTS DBA_TBL(START_TIME Timestamp, SESSION_ID CHAR(19), USER_ID VARCHAR(200), SCHEMA_NAME VARCHAR(200), SCRIPT_NAME VARCHAR(200),  QUERY VARCHAR(1000))
          ]])
    query([[commit]])

    local s_suc, s_res = pquery([[SELECT SESSION_ID from EXA_DBA_SESSIONS
                              WHERE SESSION_ID > 4
                                AND SESSION_ID != (SELECT CURRENT_SESSION)
                              order by 1 
                             ]])
    if not s_suc then 
       output('Lua query failed and aborting process with no action taken!, query_return_code='..tostring(s_suc))
       goto bypass
    end /*end-if*/

   /*------------------------------------------------------
    Kill all sessions but the one running this one
    ------------------------------------------------------*/
    output("===============================================")
    output("Killing sessions.")
    output("===============================================")

    k=1
    for k=1,#s_res do
        local my_kill = 'KILL SESSION '..s_res[k][1]
        output("Trying "..my_kill)
        local kill_suc, kill_res = pquery(my_kill)
            
    if not kill_suc then
        output('Lua query failed for killing session '..s_res[k][1]..'. Aborting process!')
        goto bypass
    end /*end-if*/ 

end /*end-for*/

    /*------------------------------------------------------
    Create and execute REVOKES
    ------------------------------------------------------*/
    output("===============================================")
    output("Saving off GRANTS before doing REVOKE.")
    output("===============================================")


    q_suc, q_res = pquery([[SELECT GRANTEE from EXA_DBA_SYS_PRIVS
                          WHERE GRANTEE NOT IN ('SYS', 'DBA')
                            AND PRIVILEGE = 'CREATE SESSION'
                            order by 1 
                             ]])
    if not q_suc then 
       output('Lua query failed and aborting process with no action taken!, query_return_code='..tostring(q_suc))
       goto bypass
    end/*end-if*/

    /* Lua likes local strings, so define and use in followin query*/
    grant_string="GRANT CREATE SESSION TO  "

    for i=1,#q_res do
        local semi = ";"
        output("--GRANT CREATE SESSION TO  "..q_res[i][1]..";")
        local suc1, res1 = pquery([[
            INSERT INTO "DBA_TBL" values(:o,:ses, :uzr,:sch, :scr,:lgs ||:qu)]],{o=start_time, ses=session, uzr=user, sch=schema, scr=script, lgs=grant_string, qu=q_res[i][1]..semi})
         
        if not suc1 then
           output(res1.error_message)
        end -- END if
    end -- END for      

output("===============================================")
output("REVOKE CREATE SESSIONS")
output("===============================================")

i=1
for i=1,#q_res do
    local my_sql = 'REVOKE CREATE SESSION FROM '..q_res[i][1]..';'
    output('Trying '..my_sql)
    local rev_suc, rev_res = pquery(my_sql)
        
    if not rev_suc then
        output('Lua query failed for revoking '..q_res[i][1]..'. Aborting process!')
        goto bypass
    end  --end-if
   
end --end-for

::bypass::
output("===============================================")
output("Script has ended.")
output("===============================================")
/
;
execute script attempt() with output;

select * from RETAIL.DBA_TBL;

select * from EXA_DBA_SYS_PRIVS WHERE GRANTEE NOT IN ('SYS','DBA');