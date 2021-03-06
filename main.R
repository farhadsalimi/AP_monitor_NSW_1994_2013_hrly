
#### name:main ####

# NSW air quality data (received from EPA) -----
library (dplyr)
library(openair)
library(reshape2)
library(stringr)
library(tidyr)
library(readr)
library(lubridate)

projdir <- "Q:/Research/Environment_General/Air_Pollution_Monitoring_Stations_NSW/AP_monitor_NSW_1994_2013_hrly/"
setwd(projdir)
dir()
indir  <- "data_provided"
dir(indir)

#importing the data (using the openair import function in combination with tb_df)
nsw9498 <-  tbl_df (import (file.path("data_provided", "/OEH (1994-1998)_AllSites_1hrlyData.csv")))
nsw9903 <-  tbl_df (import (file.path("data_provided", "/OEH (1999-2003)__AllSites_1hrlyData.csv")))
nsw0408 <-  tbl_df (import (file.path("data_provided", "/OEH (2004-2008)__AllSites_1hrlyData.csv")))
nsw0913 <-  tbl_df (import (file.path("data_provided", "/OEH (2009-2013)__AllSites_1hrlyData.csv")))

# remove the units
names(nsw9498)[2:ncol(nsw9498)] <- word(colnames(nsw9498)[2:ncol(nsw9498)], start = 1, end = -2)
names(nsw9903)[2:ncol(nsw9903)] <- word(colnames(nsw9903)[2:ncol(nsw9903)], start = 1, end = -2)
names(nsw0408)[2:ncol(nsw0408)] <- word(colnames(nsw0408)[2:ncol(nsw0408)], start = 1, end = -2)
names(nsw0913)[2:ncol(nsw0913)] <- word(colnames(nsw0913)[2:ncol(nsw0913)], start = 1, end = -2)

# importing sites locations data
nsw.locations <- read_csv(file.path("data_provided", "/locations.csv"))

# binding them together
nswaq9413 <- bind_rows (nsw9498,nsw9903,nsw0408, nsw0913)

# removing the unnecessary data
remove (nsw9498,nsw9903,nsw0408, nsw0913)

#lowercase the column names
names(nswaq9413) <- tolower(colnames(nswaq9413))

#convert all columns but date to "double"
cols = seq(from=2, to=ncol(nswaq9413));
# this next line could be made more efficient.
nswaq9413[,cols] = apply(nswaq9413[,cols], 2, function(x) as.double(as.character(x)))

# remove the columns which all values are NA's
nswaq9413 <- nswaq9413[,colSums(is.na(nswaq9413))< nrow(nswaq9413)]

# keep the variables of interest (pm2.5, pm10, o3, no, co, humidity, and temperature)
nswaq9413 <- nswaq9413 %>%
  select (date, contains ("pm2.5"), contains("pm10"), contains ("ozone"), contains ("hum"), contains ("tem"), contains ("no"), contains ("co"), contains ("so2"))


#### TODO check if we might alternatively set these to zero, or some
#### code to allow sens test?
# replace all negative values with NA
nswaq9413 [nswaq9413 < 0] <- NA

# check the class of each column
lapply (nswaq9413, class)
write.table(nswaq9413, 'data_derived/nswaq9413.hrly.csv', row.names = F, sep  = ",")
library(disentangle)
str(nswaq9413)
dd <- data_dictionary(as.data.frame(nswaq9413))
write.csv(dd, "data_derived/nswaq9413.hrly.data_dictionary.csv", row.names = F)
vl <- variable_names_and_labels(datadict=dd)
write.csv(vl, "data_derived/nswaq9413.hrly.variable_names_and_labels.csv", row.names = F)
remove(dd, vl)
# calculate the daily average (at least 75% of data needed for each day otherwise NA)
# WS and WD data should not be averaged using this approach (the columns heading needs to change to ws and wd firstly)
nswaq9413.daily.avg <- timeAverage (nswaq9413, avg.time = "day", data.thresh = 75, interval = "hour")
nswaq9413.daily.1hrmax <- timeAverage (nswaq9413, avg.time = "day", statistic = "max", data.thresh = 75, interval = "hour") %>%
  select ( contains("date"), contains ("no2"), contains ("ozone"))
colnames <- colnames (nswaq9413.daily.1hrmax)
colnames <- gsub ("no2","no2max",colnames)
colnames <- gsub ("ozone","o3max",colnames) 
colnames (nswaq9413.daily.1hrmax) <- colnames

nswaq9413.daily <- left_join (nswaq9413.daily.avg, nswaq9413.daily.1hrmax)

# make a long formatted data
nswaq9413.daily.long <- melt (nswaq9413.daily, id = "date", value.name = "concentration")

# splitting the variable to site and the type of observation
site <- word (nswaq9413.daily.long$variable,start = 1, end = 3) # get the first 3 words (some sites' names include more than one word)

# remove unnecessary words to get down to the site name only
site <- gsub ("1h","",site)
site <- gsub (" o3max", "", site)
site <- gsub (" no2max", "", site)
site <- gsub (" pm10","",site)
site <- gsub (" pm2.5","",site)
site <- gsub (" temp","",site)
site <- gsub (" humid", "", site)
site <- gsub (" ozone", "", site)
site <- gsub (" nox", "", site)
site <- gsub (" no2", "", site)
site <- gsub (" no", "", site)
site <- gsub (" co", "", site)
site <- gsub (" so2", "", site)

site <- str_trim(site, side = "both") #remove space from both sides of the name 
site <- gsub (" ", ".", site) #replace space with dot

#remove space from both side 
variable <- str_trim(nswaq9413.daily.long$variable, side = "both") 
variable <- word(variable, -3) # get the 3rd word from the end (it is what we want (the name of the variable))
variables <- c ("humid" = "humidity", "ozone" = "o3", "pm10" ="pm10", "pm2.5" = "pm2.5", "temp" = "temp", "co" = "co", "no" = "no", "no2" = "no2", "nox" = "nox", "so2" = "so2", "no2max" = "no2max", "o3max" = "o3max")

# add the "observation" and "site" column to our data
nswaq9413.daily.long$observation <- factor (variables[variable], levels = variables)
nswaq9413.daily.long$site <- site

# remove unnecessary data
remove (site,variable,variables)

# build the tidy data (each column a variable)
nswaq9413.daily <- 
  tbl_df(nswaq9413.daily.long) %>%
  select (-variable) %>%
  filter (!is.na(observation)) %>%
  spread (observation, concentration) %>%
  arrange (site)

# removing unnecessary data
remove (nswaq9413.daily.long)

# attach the sites locations (lon and lat)
nswaq9413.daily <- left_join (nswaq9413.daily, nsw.locations)

# remove unnecessary data
remove (nsw.locations,nswaq9413.daily.avg,nswaq9413.daily.1hrmax)

# change date format to Date
nswaq9413.daily <- nswaq9413.daily %>% mutate (date = as.Date(date))

#subsetting to sydney stations
nswaq9413.daily.sydney <- nswaq9413.daily %>%
  filter ( site %in% c ("bringelly", "camden", "chullora", "campbelltown.west","earlwood","lindfield","liverpool","oakdale","prospect","randwick","richmond","rozelle","st.marys","vineyard")) 

# selecting the sites which have at least 75% of data available for each variable
sites <- nswaq9413.daily.sydney %>%
  group_by (site) %>%
  summarise (total.count = n(), na.pm2.5 = sum(is.na(pm2.5)), na.pm10 = sum(is.na(pm10)), na.humidity = sum(is.na(humidity)), na.o3 = sum(is.na(o3)), na.o3max = sum(is.na(o3max)), na.temp = sum(is.na(temp)), na.co = sum(is.na(co)), na.no = sum(is.na(no)), na.no2 = sum(is.na(no2)), na.nox = sum(is.na(nox)), na.so2 = sum(is.na(so2))) %>%
  mutate (pm2.5.na.percent = na.pm2.5/total.count, pm10.na.percent = na.pm10/total.count, humidity.na.percent = na.humidity/total.count, o3.na.percent = na.o3/total.count,o3max.na.percent = na.o3max/total.count, temp.na.percent = na.temp/total.count, co.na.percent = na.co/total.count, no.na.percent = na.co/total.count, no2.na.percent = na.no2/total.count, nox.na.percent = na.nox/total.count, so2.na.percent = na.so2/total.count)

pm2.5.sites <- data.frame(site=c("earlwood","liverpool","richmond"))
pm10.sites <- sites %>% filter (pm10.na.percent <= 0.25) %>% select (site)  
o3.sites <- sites %>% filter (o3.na.percent <= 0.25) %>% select (site)
o3max.sites <- sites %>% filter (o3max.na.percent <= 0.25) %>% select (site)
humidity.sites <- sites %>% filter (humidity.na.percent <= 0.25) %>% select (site)
temp.sites <- sites %>% filter (temp.na.percent <= 0.25) %>% select (site)
co.sites <- sites %>% filter (co.na.percent <= 0.25) %>% select (site)
no.sites <- sites %>% filter (no.na.percent <= 0.25) %>% select (site)
no2.sites <- sites %>% filter (no2.na.percent <= 0.25) %>% select (site)
nox.sites <- sites %>% filter (nox.na.percent <= 0.25) %>% select (site)
so2.sites <- sites %>% filter (so2.na.percent <= 0.25) %>% select (site)

nswaq9413.pm2.5.daily.sydney <- left_join (pm2.5.sites, nswaq9413.daily.sydney)
nswaq9413.pm10.daily.sydney <- left_join (pm10.sites, nswaq9413.daily.sydney)
nswaq9413.o3.daily.sydney <- left_join (o3.sites, nswaq9413.daily.sydney)
nswaq9413.o3max.daily.sydney <- left_join (o3max.sites, nswaq9413.daily.sydney)
nswaq9413.humidity.daily.sydney <- left_join (humidity.sites, nswaq9413.daily.sydney)
nswaq9413.temp.daily.sydney <- left_join (temp.sites, nswaq9413.daily.sydney)
nswaq9413.co.daily.sydney <- left_join (co.sites, nswaq9413.daily.sydney)
nswaq9413.no.daily.sydney <- left_join (no.sites, nswaq9413.daily.sydney)
nswaq9413.no2.daily.sydney <- left_join (no2.sites, nswaq9413.daily.sydney)
nswaq9413.nox.daily.sydney <- left_join (nox.sites, nswaq9413.daily.sydney)
nswaq9413.so2.daily.sydney <- left_join (so2.sites, nswaq9413.daily.sydney)

#pm2.5 imputation
data <- nswaq9413.pm2.5.daily.sydney %>% select (date, site, pm2.5)
data <- data %>% mutate (month = month(date), year = year(date)) %>%
  mutate(season = ifelse (month == 12 | month ==1 | month == 2, "summer",.) %>%
           ifelse (month == 3 | month == 4 | month == 5,"autumn",.) %>%
           ifelse(month == 6 | month ==7 | month == 8, "winter",.) %>%
           ifelse(month == 9 | month ==10 | month == 11, "spring",.)) %>%
  mutate (season = as.character(season))

data.siteaverage <- data %>% group_by(site,year,season) %>% summarise(site.mean.pm2.5 = mean(pm2.5, na.rm =TRUE))

data.othersitesaverage2 <- data %>% filter (site != "earlwood") %>% group_by(year,season) %>% summarise(othersites.mean.pm2.5 = mean(pm2.5, na.rm =TRUE)) %>% mutate(site="earlwood")
data.othersitesaverage3 <- data %>% filter (site != "liverpool") %>% group_by(year,season) %>% summarise(othersites.mean.pm2.5 = mean(pm2.5, na.rm =TRUE)) %>% mutate(site="liverpool")
data.othersitesaverage4 <- data %>% filter (site != "richmond") %>% group_by(year,season) %>% summarise(othersites.mean.pm2.5 = mean(pm2.5, na.rm =TRUE)) %>% mutate(site="richmond")

data.othersitesaverage <-  rbind_list(data.othersitesaverage2,data.othersitesaverage3,data.othersitesaverage4)

data.siteandotheraverage <- full_join(data.siteaverage,data.othersitesaverage)
data.siteandotheraverage <- data.siteandotheraverage %>% mutate (factor = site.mean.pm2.5/othersites.mean.pm2.5)

data.dailyaverage <- data %>% group_by (date) %>% summarise (mean.pm2.5 = mean(pm2.5, na.rm = TRUE)) %>%
  mutate (month = month(date), year = year(date)) %>% 
  mutate(season = ifelse (month == 12 | month ==1 | month == 2, "summer",.) %>%
           ifelse (month == 3 | month == 4 | month == 5,"autumn",.) %>%
           ifelse(month == 6 | month ==7 | month == 8, "winter",.) %>%
           ifelse(month == 9 | month ==10 | month == 11, "spring",.)) %>%
  mutate (season = as.character(season))
data.impute <- left_join (data.dailyaverage,data.siteandotheraverage)
data.impute <- data.impute %>% mutate (pm2.5.impute = mean.pm2.5 * factor) %>% select (date,site,pm2.5.impute)
data.new <- left_join (data, data.impute)
data.new1 <- data.new %>% filter (is.na(pm2.5)) %>% mutate (pm2.5 = pm2.5.impute)
data.new <- data.new %>% filter (!is.na(pm2.5))
data.new <- rbind_list(data.new, data.new1)
data.new <-  data.new %>% select(-c(pm2.5.impute, season, year, month))

nswaq9413.pm2.5.daily.sydney  <- nswaq9413.pm2.5.daily.sydney %>% select(-pm2.5)
nswaq9413.pm2.5.daily.sydney <- left_join(nswaq9413.pm2.5.daily.sydney, data.new)

remove (data.othersitesaverage3,data.othersitesaverage4,data.siteaverage,data.othersitesaverage,data.siteandotheraverage,data.dailyaverage,data.impute,data.new,data.new1)

nswaq9413.pm2.5.daily.sydney <- nswaq9413.pm2.5.daily.sydney %>% group_by (date) %>% summarise (pm2.5 = mean (pm2.5, na.rm = TRUE))
nswaq9413.pm10.daily.sydney <- nswaq9413.pm10.daily.sydney %>% group_by (date) %>% summarise (pm10 = mean (pm10, na.rm = TRUE))
nswaq9413.o3.daily.sydney <- nswaq9413.o3.daily.sydney %>% group_by (date) %>% summarise (o3 = mean (o3, na.rm = TRUE))
nswaq9413.o3max.daily.sydney <- nswaq9413.o3max.daily.sydney %>% group_by (date) %>% summarise (o3max = mean (o3max, na.rm = TRUE))
nswaq9413.humidity.daily.sydney <- nswaq9413.humidity.daily.sydney %>% group_by (date) %>% summarise (humidity = mean (humidity, na.rm = TRUE))
nswaq9413.temp.daily.sydney <- nswaq9413.temp.daily.sydney %>% group_by (date) %>% summarise (temp = mean (temp, na.rm = TRUE))
nswaq9413.co.daily.sydney <- nswaq9413.co.daily.sydney %>% group_by (date) %>% summarise (co = mean (co, na.rm = TRUE))
nswaq9413.no.daily.sydney <- nswaq9413.no.daily.sydney %>% group_by (date) %>% summarise (no = mean (no, na.rm = TRUE))
nswaq9413.no2.daily.sydney <- nswaq9413.no2.daily.sydney %>% group_by (date) %>% summarise (no2 = mean (no2, na.rm = TRUE))
nswaq9413.nox.daily.sydney <- nswaq9413.nox.daily.sydney %>% group_by (date) %>% summarise (nox = mean (nox, na.rm = TRUE))
nswaq9413.so2.daily.sydney <- nswaq9413.so2.daily.sydney %>% group_by (date) %>% summarise (so2 = mean (so2, na.rm = TRUE))

nswaq9413.daily.sydney <- left_join (nswaq9413.pm2.5.daily.sydney, nswaq9413.pm10.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.o3.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.o3max.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.humidity.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.temp.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.co.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.no.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.no2.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.nox.daily.sydney)
nswaq9413.daily.sydney <- left_join (nswaq9413.daily.sydney, nswaq9413.so2.daily.sydney)

# remove unnecessary data
remove (temp.sites, sites, so2.sites, pm10.sites, pm2.5.sites, o3.sites,humidity.sites, nswaq9413.humidity.daily.sydney, nswaq9413.o3.daily.sydney,nswaq9413.o3max.daily.sydney, nswaq9413.pm10.daily.sydney,nswaq9413.so2.daily.sydney, nswaq9413.pm2.5.daily.sydney, nswaq9413.temp.daily.sydney,nswaq9413.co.daily.sydney, nswaq9413.no.daily.sydney, nswaq9413.no2.daily.sydney, nswaq9413.nox.daily.sydney , co.sites, no.sites, no2.sites, nox.sites)

# if NA's are less than 5%, replace NA with the mean of the values from the previous and next days
first_nonna_pm25_row <- min(which(!is.na(nswaq9413.daily.sydney$pm2.5)))
napercent_pm25 <- nswaq9413.daily.sydney %>% 
  slice (first_nonna_pm25_row:nrow(nswaq9413.daily.sydney)) %>%
  summarise (total.count = n(), na.pm2.5 = sum(is.na(pm2.5)), na.pm2.5.percent =100*na.pm2.5/total.count)

if (napercent_pm25$na.pm2.5.percent<5) {
  nswaq9413.daily.sydney <- nswaq9413.daily.sydney %>% arrange(date) %>%
    mutate(pm2.5_lag= lag(pm2.5), pm2.5_lead=lead(pm2.5)) %>%
    mutate(pm2.5= ifelse(is.na(pm2.5), 0.5*(pm2.5_lag+pm2.5_lead), pm2.5)) 
}  


# rounding to one decimal point
nswaq9413.daily.sydney <- nswaq9413.daily.sydney %>% mutate (pm2.5=round (pm2.5, digits=1),pm10=round (pm10, digits=1),o3=round (o3, digits=1),o3max=round (o3max, digits=1),humidity=round (humidity, digits=1),temp=round (temp, digits=1),co=round (co, digits=1),no=round (no, digits=1), no2=round (no2, digits=1), nox =round (nox, digits=1), so2 =round (so2, digits=1))

# saving the file
write_csv (nswaq9413.daily.sydney, path ="data_derived/nswaq9413.daily.sydney.csv")
dd <- data_dictionary(as.data.frame(nswaq9413.daily.sydney))
write.csv(dd, "data_derived/nswaq9413.daily.sydney.data_dictionary.csv", row.names = F)
vl <- variable_names_and_labels(datadict=dd)
write.csv(vl, "data_derived/nswaq9413.daily.sydney.variable_names_and_labels.csv", row.names = F)
