//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

//cursors
#define Default_Cursor	0
#define Client_Cursor	1
#define Server_Cursor	2
//conversions
#define TEXT_CONV		1
#define RSC_FILE_CONV	2
#define NUMBER_CONV		3
//column flag values:
#define IS_NUMERIC		1
#define IS_BINARY		2
#define IS_NOT_NULL		4
#define IS_PRIMARY_KEY	8
#define IS_UNSIGNED		16
//types
#define TINYINT		1
#define SMALLINT	2
#define MEDIUMINT	3
#define INTEGER		4
#define BIGINT		5
#define DECIMAL		6
#define FLOAT		7
#define DOUBLE		8
#define DATE		9
#define DATETIME	10
#define TIMESTAMP	11
#define TIME		12
#define STRING		13
#define BLOB		14
// TODO: Investigate more recent type additions and see if I can handle them. - Nadrew

DBConnection
	var/_db_con // This variable contains a reference to the actual database connection.
	var/con_dbi // This variable is a string containing the DBI MySQL requires.
	var/con_user // This variable contains the username data.
	var/con_password // This variable contains the password data.
	var/con_cursor // This contains the default database cursor data.
	var/con_server = ""
	var/con_port = 3306
	var/con_database = ""
	var/failed_connections = 0

DBConnection/New(server, port = 3306, database, username, password_handler, cursor_handler = Default_Cursor, dbi_handler)
	con_user = username
	con_password = password_handler
	con_cursor = cursor_handler
	con_server = server
	con_port = port
	con_database = database

	if (dbi_handler)
		con_dbi = dbi_handler
	else
		con_dbi = "dbi:mysql:[database]:[server]:[port]"

	_db_con = _dm_db_new_con()

DBConnection/proc/Connect(dbi_handler = con_dbi, user_handler = con_user, password_handler = con_password, cursor_handler)
	if (!config.sql_enabled)
		return 0
	if (!src)
		return 0
	cursor_handler = con_cursor
	if (!cursor_handler)
		cursor_handler = Default_Cursor
	return _dm_db_connect(_db_con, dbi_handler, user_handler, password_handler, cursor_handler, null)

DBConnection/proc/Disconnect()
	return _dm_db_close(_db_con)

DBConnection/proc/IsConnected()
	if(!config.sql_enabled)
		return 0
	var/success = _dm_db_is_connected(_db_con)
	return success

DBConnection/proc/Quote(str)
	return _dm_db_quote(_db_con,str)

DBConnection/proc/ErrorMsg()
	return _dm_db_error_msg(_db_con)

DBConnection/proc/SelectDB(database_name, new_dbi)
	if (IsConnected())
		Disconnect()
	con_database = database_name
	return Connect(new_dbi ? new_dbi : "dbi:mysql:[database_name]:[con_server]:[con_port]", con_user, con_password)

DBConnection/proc/NewQuery(sql_query, cursor_handler = con_cursor)
	return new/DBQuery(sql_query, src, cursor_handler)

DBQuery
	var/sql // The sql query being executed.
	var/default_cursor
	var/list/columns //list of DB Columns populated by Columns()
	var/list/conversions
	var/list/item[0]  //list of data values populated by NextRow()

	var/DBConnection/db_connection
	var/_db_query

DBQuery/New(var/sql_query, var/DBConnection/connection_handler, var/cursor_handler)
	if (sql_query)
		sql = sql_query
	if (connection_handler)
		db_connection = connection_handler
	if (cursor_handler)
		default_cursor = cursor_handler
	_db_query = _dm_db_new_query()
	return ..()

DBQuery/proc/Connect(DBConnection/connection_handler)
	db_connection = connection_handler

DBQuery/proc/Execute(var/list/argument_list = null, var/pass_not_found = 0, sql_query = sql, cursor_handler = default_cursor)
	Close()

	if (argument_list)
		sql_query = parseArguments(sql_query, argument_list, pass_not_found)

	var/result = _dm_db_execute(_db_query, sql_query, db_connection._db_con, cursor_handler, null)

	if (ErrorMsg())
		error("SQL Error: '[ErrorMsg()]'")

	return result

DBQuery/proc/NextRow()
	return _dm_db_next_row(_db_query,item,conversions)

DBQuery/proc/RowsAffected()
	return _dm_db_rows_affected(_db_query)

DBQuery/proc/RowCount()
	return _dm_db_row_count(_db_query)

DBQuery/proc/ErrorMsg()
	return _dm_db_error_msg(_db_query)

DBQuery/proc/Columns()
	if (!columns)
		columns = _dm_db_columns(_db_query,/DBColumn)
	return columns

DBQuery/proc/GetRowData()
	var/list/columns = Columns()
	var/list/results
	if (columns.len)
		results = list()
		for (var/C in columns)
			results += C
			var/DBColumn/cur_col = columns[C]
			results[C] = item[(cur_col.position+1)]
	return results

DBQuery/proc/Close()
	item.len = 0
	columns = null
	conversions = null
	return _dm_db_close(_db_query)

DBQuery/proc/Quote(str)
	return db_connection.Quote(str)

DBQuery/proc/SetConversion(column,conversion)
	if (istext(column))
		column = columns.Find(column)
	if (!conversions)
		conversions = new/list(column)
	else if (conversions.len < column)
		conversions.len = column
	conversions[column] = conversion

/* Works similarly to the PDO object's Execute() method in PHP.
* Insert a list of keys/values, it searches the SQL syntax for the keys,
* and replaces them with sanitized versions of the values.
* Can be called independently, or through dbcon.Execute(), where the list would be the first argument.
* passNotFound controls whether or not is passes keys not found in the SQL query.
* Keys are /case-sensitive/, be careful!
* Returns the parsed SQL query upon completion.
* - Skull132
*/
/DBQuery/proc/parseArguments(var/query_to_parse = null, var/list/argument_list, var/pass_not_found = 0)
	if (!query_to_parse || !argument_list || !argument_list.len)
		log_debug("parseArguments() failed! Improper arguments sent!")
		return 0

	for (var/placeholder in argument_list)
		if (!findtextEx(query_to_parse, placeholder))
			if (pass_not_found)
				continue
			else
				log_debug("parseArguments() failed! Key not found: [placeholder].")
				return 0

		var/argument = argument_list[placeholder]

		if (istext(argument))
			argument = dbcon.Quote(argument)
		else if (isnum(argument))
			argument = "[argument]"
		else if (istype(argument, /list))
			argument = parse_db_lists(argument)
		else if (isnull(argument))
			argument = "NULL"
		else
			log_debug("parseArguments() failed! Cannot identify argument!")
			log_debug("Placeholder: '[placeholder]'. Argument: '[argument]'")
			return 0

		query_to_parse = replacetextEx(query_to_parse, placeholder, argument)

	return query_to_parse

/DBQuery/proc/parse_db_lists(var/list/argument)
	if (!argument || !istype(argument) || !argument.len)
		return "NULL"

	var/text = ""
	var/count = argument.len
	for (var/i = 1, i <= count, i++)
		if (isnum(argument[i]))
			text += "[argument[i]]"
		else
			text += dbcon.Quote(argument[i])

		if (i != count)
			text += ", "

	return "([text])"

DBColumn
	var/name
	var/table
	var/position //1-based index into item data
	var/sql_type
	var/flags
	var/length
	var/max_length

DBColumn/New(name_handler, table_handler, position_handler, type_handler, flag_handler, length_handler, max_length_handler)
	name = name_handler
	table = table_handler
	position = position_handler
	sql_type = type_handler
	flags = flag_handler
	length = length_handler
	max_length = max_length_handler
	return ..()


DBColumn/proc/SqlTypeName(type_handler = sql_type)
	switch (type_handler)
		if (TINYINT)
			return "TINYINT"
		if (SMALLINT)
			return "SMALLINT"
		if (MEDIUMINT)
			return "MEDIUMINT"
		if (INTEGER)
			return "INTEGER"
		if (BIGINT)
			return "BIGINT"
		if (FLOAT)
			return "FLOAT"
		if (DOUBLE)
			return "DOUBLE"
		if (DATE)
			return "DATE"
		if (DATETIME)
			return "DATETIME"
		if (TIMESTAMP)
			return "TIMESTAMP"
		if (TIME)
			return "TIME"
		if (STRING)
			return "STRING"
		if (BLOB)
			return "BLOB"


#undef Default_Cursor
#undef Client_Cursor
#undef Server_Cursor
#undef TEXT_CONV
#undef RSC_FILE_CONV
#undef NUMBER_CONV
#undef IS_NUMERIC
#undef IS_BINARY
#undef IS_NOT_NULL
#undef IS_PRIMARY_KEY
#undef IS_UNSIGNED
#undef TINYINT
#undef SMALLINT
#undef MEDIUMINT
#undef INTEGER
#undef BIGINT
#undef DECIMAL
#undef FLOAT
#undef DOUBLE
#undef DATE
#undef DATETIME
#undef TIMESTAMP
#undef TIME
#undef STRING
#undef BLOB
