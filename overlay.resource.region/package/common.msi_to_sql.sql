DECLARE @DB_NAME varchar(256);
DECLARE @MSI_NAME varchar(256);
SET @MSI_NAME = '${SERVICE_MSI_NAME}';
SET @DB_NAME = (select name from (select CAST(sid AS UNIQUEIDENTIFIER) AS [uuid], [name] from sys.database_principals) AS uuid where uuid = CAST('${IDENTITY_CLIENTID}' AS UNIQUEIDENTIFIER));

IF (@DB_NAME is not null and @DB_NAME = '')
    BEGIN
        SET @MSI_NAME = @DB_NAME;
    END

IF (@DB_NAME is null or @DB_NAME = '')
    BEGIN
        DECLARE @command nvarchar(4000);
        SET @command = 'CREATE USER [' + @MSI_NAME + '] WITH SID = ' + CONVERT(VARCHAR(1000), CAST(CAST('${IDENTITY_CLIENTID}' AS UNIQUEIDENTIFIER) AS varbinary(16)), 1) + ', TYPE=E';
        EXEC sp_executesql @command;
    END
EXEC sp_addrolemember '${DB_ROLE}', @MSI_NAME;
