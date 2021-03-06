suppressPackageStartupMessages(library(dwtools))

# Setup db connections --------------------------------------------------------------------

##### define your connections
# csv and SQLite works out of the box without configuration outside of R.
# examples are on three instances of sqlite and a csv.

library(RSQLite) # install.packages("RSQLite")
sqlite1 = list(drvName="SQLite",dbname="sqlite1.db")
sqlite1$conn = dbConnect(SQLite(), dbname=sqlite1$dbname)
sqlite2 = list(drvName="SQLite",dbname="sqlite2.db")
sqlite2$conn = dbConnect(SQLite(), dbname=sqlite2$dbname)
sqlite3 = list(drvName="SQLite",dbname="sqlite3.db")
sqlite3$conn = dbConnect(SQLite(), dbname=sqlite3$dbname)
csv1 = list(drvName = "csv")

# configure connections
options("dwtools.db.conns"=list(sqlite1=sqlite1,sqlite2=sqlite2,sqlite3=sqlite3,csv1=csv1))

## external dependencies required
# library(RPostgreSQL) # install.packages("RPostgreSQL")
# psql1 <- list(drvName="PostgreSQL", host="localhost", port="5432", dbname="dwtools", user="dwtools")
# psql1$conn <- dbConnect(PostgreSQL(), host=psql1$host, port=psql1$port, dbname=psql1$dbname, user=psql1$user, password="dwtools_pass")
# library(RMySQL) # install.packages("RMySQL")
# mysql1 = list(drvName="MySQL", host="localhost", port="3306", dbname="dwtools", user="dwtools")
# mysql1$conn <-dbConnect(MySQL(), host=mysql1$host, port=mysql1$port, dbname=mysql1$dbname, user=mysql1$user, password="dwtools_pass")
# library(RODBC) # install.packages("RODBC")
# odbc1 <- list(drvName="ODBC", user="dwtools", dbname="dwtools", dsn="mydsn")
# odbc1$conn <- odbcConnect(dsn=odbc1$dsn, uid=odbc1$user, pwd="dwtools_pass")

# Basic usage --------------------------------------------------------------------

(DT = dw.populate(1e5,scenario="fact")) # fact table

### write, aka INSERT + CREATE TABLE

db(DT,"my_tab1") # write to db, using default db connection (first in list)
db(DT,"my_tab2","sqlite2") # WRITE to my_tab_alt to sqlite2 connection
db(DT,"my_tab1","csv1") # WRITE to my_tab1.csv
r1 = db(DT) # write to auto named table in default db connection (first in list)
attr(r1,'tablename',TRUE) # auto generated table name # ?auto.table.name
r2 = db(DT,NULL,"sqlite2") # the same above but another connection, override r1 attribute! read ?db note
attr(r2,'tablename',TRUE)
l = db(DT,c("my_tab11","my_tab22"),c("sqlite1","sqlite2")) # save into different connections and different tables
attr(l,'tablename',TRUE)

### read, aka: SELECT * FROM 

db("my_tab1")
db("my_tab2","sqlite2")
db("my_tab1","csv1") # READ from my_tab1.csv
r1 = db("my_tab1","sqlite1",key=c("prod_code","cust_code","geog_code","time_code")) # set key on result, useful on chaining, see 'Chaining data.table' examples below
key(r1)
db(DT, "my_tab2") # CREATE TABLE just for below line example
l = db("my_tab2", c("sqlite1","sqlite2")) # read my_tab2 table from two connections, return list
str(l)
l = db(c("my_tab11","my_tab22"), c("sqlite1","sqlite2")) # read my_tab1 and my_tab2 table from two connections, return list
str(l)

### get, aka: SELECT ... FROM ... JOIN ...

db("SELECT * FROM my_tab1")
r = db("SELECT * FROM my_tab2","sqlite2",key=c("prod_code","cust_code","geog_code","time_code"))
key(r)
l = db(c("SELECT * FROM my_tab1","SELECT * FROM my_tab2"),c("sqlite1","sqlite2"))
str(l)

### send, aka: UPDATE, INDEX, DROP, etc.

db(c("CREATE INDEX idx_my_tab1a ON my_tab1 (prod_code, geog_code)","CREATE INDEX idx_my_tab1b ON my_tab1 (cust_code, time_code)")) # create two indices
db(c("DROP INDEX idx_my_tab1a","DROP INDEX idx_my_tab1b")) # drop two indices
db("DROP TABLE my_tab2") # drop the table which we created in above example #CREATE TABLE
db(c("DROP TABLE my_tab1","DROP TABLE my_tab2"),c("sqlite1","sqlite2")) # multiple statements into multiple connections

# Advanced usage ------------------------------------------------------

options("dwtools.verbose"=1L)
db.conns.names = c("sqlite1","sqlite2","sqlite3")

### easy sql scripting: DROP ALL TABLES IN ALL DBs
(DT = dw.populate(1e5,scenario="fact")) # fact table

# populate 2 tables in sqlite3 while chaining: db(DT,NULL,"sqlite3"), auto table names
DT[,db(.SD,NULL,c("sqlite3","sqlite3"))]

# populate 2 tables in each connection, then 1 table in each connection, 9 tables created
DT[,db(.SD,NULL,rep(db.conns.names,2))][,db(.SD,NULL,db.conns.names)]

# query all tables on all connections
(tbls = db("SELECT name FROM sqlite_master WHERE type='table'",db.conns.names))

# drop all tables on all connections
ll = lapply(1:length(tbls), function(i, tbls){
  if(nrow(tbls[[i]]) > 0) data.table(conn_name = names(tbls[i]), tbls[[i]])
  else data.table(conn_name = character(), tbls[[i]])
}, tbls)
r = rbindlist(ll)[,list(sql=paste0("DROP TABLE ",name), conn_name=conn_name, name=name) # build statement
                  ][,list(conn_name=conn_name, name=name, res=db(sql,conn_name)) # exec DROP TABLE ...
                    ]
# verify tables dropped
db("SELECT name FROM sqlite_master WHERE type='table'",db.conns.names)

### Chaining data.table: DT[...][...]

# populate star schema to db
X = dw.populate(1e5,scenario="star") # list of 5 tables, 1 fact table and 4 dimensions
db(X$TIME,"time") # save time to db
db(X$GEOGRAPHY,"geography") # save geography to db
db(X$SALES,"sales") # save sales FACT to db

# data.table join in R directly on external SQL database
db("geography",key="geog_code")[db("sales",key="geog_code")] # geography[sales]

options("dwtools.timing"=TRUE) # turn on db auditing
## Chaining including multiple read and multiple write directly on SQL database
# 0. predefine aggregate function for later use
# 1. query sales fact table from db
# 2. aggregate to 2 dimensions
# 3. save current state of data to db
# 4. query geography dimension table from db
# 5. sales left join geography dimension
# 6. aggregate to higher geography entity
# 7. save current state of data to db
# 8. query time dimension table from db
# 8. sales left join time dimension
# 9. aggregate to higher time entity
# 10. save current state of data to db
jj_aggr = quote(list(amount=sum(amount), value=sum(value)))
r <- db("sales",key="geog_code" # read fact table from db
        )[,eval(jj_aggr),keyby=c("geog_code","time_code") # aggr by geog_code and time_code
          ][,db(.SD) # write to db, auto.table.name
            ][,db("geography",key="geog_code" # read lookup geography dim from db
                  )[.SD # left join geography
                    ][,eval(jj_aggr), keyby=c("time_code","geog_region_name")] # aggr
              ][,db(.SD) # write to db, auto.table.name
                ][,db("time",key="time_code" # read lookup time dim from db
                      )[.SD # left join time
                        ][, eval(jj_aggr), keyby=c("geog_region_name","time_month_code","time_month_name")] # aggr
                  ][,db(.SD) # write to db, auto.table.name
                    ]
db("SELECT name FROM sqlite_master WHERE type='table'")
get.timing()

## Interesting to consider is
# how much effort would such 'query' requires if developing it in (leading commercial) ETL tools?
# can the classic ETL tools even compete with data.table transformation performance, and DBI loading/writing performance?
# free 'express' edition of ETL tools do have a processing row limit so cannot be well benchmarked.

### Copy tables

# dbCopy multiple tables from source to target # ?dbCopy
dbCopy(
  c("sales","geography","time"),"sqlite1", # source
  c("sales","geography","time"),"sqlite2"  # target
)
(tbls = db("SELECT name FROM sqlite_master WHERE type='table'","sqlite2")) # sqlite2 check
get.timing()
options("dwtools.timing"=FALSE)
purge.timing()

# Disconnecting and cleaning workspace ------------------------------------------------------

db.conns.names = c("sqlite1","sqlite2","sqlite3")
sapply(getOption("dwtools.db.conns")[names(getOption("dwtools.db.conns")) %in% db.conns.names],
       function(x) dbDisconnect(x[["conn"]])) # close SQLite connections
sapply(getOption("dwtools.db.conns")[names(getOption("dwtools.db.conns")) %in% db.conns.names],
       function(x) file.remove(x[["dbname"]])) # remove SQLite db files
options("dwtools.db.conns"=NULL) # reset dwtools.db.conns option
sapply(paste(c("my_tab1"),"csv",sep="."), function(x) file.remove(x)) # remove csv tables
