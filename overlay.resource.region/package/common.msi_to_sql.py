#!/usr/bin/python3
import pyodbc
import os
import requests
import struct

serverAddress = os.environ.get("SQLADDRESS")
database = os.environ.get("DB_NAME")
objectId = os.environ.get("EV2_MSI_OBJECTID")
msiName = os.environ.get("SERVICE_MSI_NAME")
msiClientId = os.environ.get("IDENTITY_CLIENTID")
dbRole = os.environ.get("DB_ROLE")
driver = "{ODBC Driver 17 for SQL Server}"
database_suffix = os.environ.get("SQLSERVER_DATABASE_SUFFIX")
deploy_env = os.environ.get("DEPLOY_ENV")
e2e_password = os.environ.get("AKS_E2E_SQL_PW")
e2e_user = os.environ.get("AKS_E2E_SQL_USER")
region = os.environ.get("REGION")

def get_bearer_token(resource_uri):
    token_auth_uri = f"http://169.254.169.254/metadata/identity/oauth2/token?resource={resource_uri}&api-version=2019-08-01&object_id={objectId}"
    head_msi = {'Metadata': "true"}

    resp = requests.get(token_auth_uri, headers=head_msi)
    access_token = resp.json()['access_token']
    return access_token

def is_deploy_env_e2e(deploy_env):
    return deploy_env == 'e2e' or deploy_env == 'corptest' or deploy_env == 'corpdev'

def construct_connStr(serverName, database, objectId):
    if is_deploy_env_e2e(deploy_env):
        return f'Driver={driver};Server=tcp:{serverName},1433;Database={database};UID={e2e_user};PWD={e2e_password}'
    return f'Driver={driver};Server=tcp:{serverName},1433;Database={database}'


def set_msi_role(msiName, connStr):
    print(f"Deploy env is: {deploy_env}")
    if not is_deploy_env_e2e(deploy_env):
        accessToken = bytes(get_bearer_token("https://" + database_suffix + "/"), 'utf-8')
        exptoken = b""
        for i in accessToken:
            exptoken += bytes({i})
            exptoken += bytes(1)
        tokenstruct = struct.pack("=i", len(exptoken)) + exptoken
        conn = pyodbc.connect(connStr, autocommit=True, attrs_before={1256: bytearray(tokenstruct)})
    else:
        conn = pyodbc.connect(connStr, autocommit=True)
    with conn.cursor() as cursor:
        try:
            result = cursor.execute(f"select name from (select CAST(sid AS UNIQUEIDENTIFIER) AS [uuid], [name] from sys.database_principals) AS uuid where uuid = CAST('{msiClientId}' AS UNIQUEIDENTIFIER);").fetchone()
            print(result)
            if result is not None and result != msiName:
                print(f"updating name from: {msiName} to dbname: {result.name}")
                msiName = result.name
            if result is None:
                print(f"SQL user does not exist for msi: {msiClientId}")
                sid = cursor.execute(
                    f"SELECT CONVERT(VARCHAR(1000), CAST(CAST('{msiClientId}' AS UNIQUEIDENTIFIER) AS VARBINARY(16)), 1) SID;").fetchone()
                cursor.execute(f"CREATE USER [{msiName}] WITH SID = {sid[0]}, TYPE=E;")
            cursor.execute(f"ALTER ROLE {dbRole} ADD MEMBER [{msiName}];")
        except pyodbc.Error as ex:
            print(f"Pyodbc Error: {ex}")
            conn.close()
            exit(2)
        except Exception as ex:
            print(f"Exception: {ex}")
            conn.close()
            exit(2)
    conn.close()


connString = construct_connStr(serverAddress, database, objectId)
print(f"Setting sql permissions for {msiName}")
set_msi_role(msiName, connString)
