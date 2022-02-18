
######################################################################## Extra Packages

library(tidyverse)
library(maps)
library(viridis)
library(ggthemes)
library(readxl)
library(dplyr)
library(plyr)
library(dbplyr)
library(haven)
library(plm)
library(lmtest)
library(haven)
require(aod)
require(ggplot2)
library(foreign) 
library(stargazer)
library(stringr)

library(rlang)

library(httr)
library(RCurl)
library(ggmap)
library(curl)

library(MatchIt)
library(dplyr)

library(zipcode)


######################################################################## Used Packages
library(RODBC)
library(wru)

######################################################################## Connection to Database
connectionString = "Driver={ODBC Driver 13 for SQL Server};
Server=10.4.0.4; 
Database=BatchImportABCBS;
Uid=aleport;
Pwd=n64ygPfya3zh;
Encrypt=yes;
TrustServerCertificate=yes;
Connection Timeout=30;"

ds_conn <- odbcDriverConnect(connectionString) # Open your RODBC connection

elig_pop <- sqlQuery(ds_conn, "select * from Datalogy.aleport.Race_Components_County",  as.is = TRUE)
View(elig_pop)

######################################################################## WRU Necessary Elements

#elig_pop$surname <- elig_pop$LastName
#elig_pop$sex <- elig_pop$female
#elig_pop$age <- elig_pop$AGE
#elig_pop$state <- elig_pop$ST_CD
#elig_pop$county <- elig_pop$MBR_COUNTY
#elig_pop$county <- str_pad(elig_pop$county, width = 3, side = "left", pad = "0")

######################################################################## Lst Name only
#surnamesretry <- str_split_fixed(COVID_EXCHANGE_MBRS$FULL_NAME, ", ", 2)
#View(surnamesretry)

#COVID_EXCHANGE_MBRS_2 <- cbind(surnamesretry,COVID_EXCHANGE_MBRS )
#View(COVID_EXCHANGE_MBRS_2)
#COVID_EXCHANGE_MBRS_2$surname <- COVID_EXCHANGE_MBRS_2$`1`


######################################################################## Finding Racial data (imputed)

census_imputed_ARFL <- get_census_data(key = "73a46888f38132dc9d24fb83cec3d3811703e246", 
                                       #states = c("AR", "TX", "TN", "MO", "OK", "LA", "MS"), 
                                       states = c( "AK"
                                                   ,"AL"
                                                   ,"AR"
                                                   ,"AZ"
                                                   ,"CA"
                                                   ,"CO"
                                                   ,"CT"
                                                   ,"DC"
                                                   ,"DE"
                                                   ,"FL"
                                                   ,"GA"
                                                   ,"HI"
                                                   ,"IA"
                                                   ,"ID"
                                                   ,"IL"
                                                   ,"IN"
                                                   ,"KS"
                                                   ,"KY"
                                                   ,"LA"
                                                   ,"MA"
                                                   ,"MD"
                                                   ,"ME"
                                                   ,"MI"
                                                   ,"MN"
                                                   ,"MO"
                                                   ,"MS"
                                                   ,"MT"
                                                   ,"NC"
                                                   ,"ND"
                                                   ,"NE"
                                                   ,"NH"
                                                   ,"NJ"
                                                   ,"NM"
                                                   ,"NV"
                                                   ,"NY"
                                                   ,"OH"
                                                   ,"OK"
                                                   ,"OR"
                                                   ,"PA"
                                                   ,"PR"
                                                   ,"RI"
                                                   ,"SC"
                                                   ,"SD"
                                                   ,"TN"
                                                   ,"TX"
                                                   ,"UT"
                                                   ,"VA"
                                                   ,"VT"
                                                   ,"WA"
                                                   ,"WI"
                                                   ,"WV"
                                                   ,"WY"),
                                       age = TRUE, 
                                       sex = TRUE, 
                                       census.geo = "county", 
                                       retry =0)
View(census_imputed_ARFL)

######################################################################## Data frame must have the above elements defined in this way otherwise it wont run

predicted_RACE <- predict_race(elig_pop, 
                               census.surname = TRUE, 
                               surname.only = FALSE, 
                               surname.year =  2010, 
                               census.geo = "county", 
                               census.key =  "", 
                               census.data = census_imputed_ARFL, 
                               age = TRUE, 
                               sex = TRUE, 
                               retry = 10 )
View(predicted_RACE)

######################################################################## Save to txt 
write.csv(predicted_RACE,"C:\\Users\\aleport\\Desktop\\SQL_Projects\\sQL_PLATFORM\\Bias\\RacialBias\\PredictedRaceCounty_ActiveMembers.csv", row.names = TRUE)
                          
######################################################################## Arron's Binary Cacluation of Race probability
predicted_RACE$white <- 0
predicted_RACE$white[predicted_RACE$pred.whi > .7]<- 1
summary(predicted_RACE$white)

predicted_RACE$black <- 0
predicted_RACE$black[predicted_RACE$pred.bla > .7]<- 1
summary(predicted_RACE$black)

predicted_RACE$hispanic <- 0
predicted_RACE$hispanic[predicted_RACE$pred.his > .7]<- 1
summary(predicted_RACE$hispanic)

predicted_RACE$asian <- 0
predicted_RACE$asian[predicted_RACE$pred.asi > .7]<- 1
summary(predicted_RACE$asian)


predicted_RACE$other <- 0
predicted_RACE$other[predicted_RACE$white != 1 & predicted_RACE$black != 1 & predicted_RACE$hispanic != 1 & predicted_RACE$asian != 1]<- 1
summary(predicted_RACE$other)

predicted_RACE$Race <- 'NA'
predicted_RACE$Race[predicted_RACE$white == 1] <- 'white'
predicted_RACE$Race[predicted_RACE$black == 1] <- 'black'
predicted_RACE$Race[predicted_RACE$hispanic == 1] <- 'hispanic'
predicted_RACE$Race[predicted_RACE$asian == 1] <- 'asian'
predicted_RACE$Race[predicted_RACE$other == 1] <- 'other'

View(predicted_RACE)
