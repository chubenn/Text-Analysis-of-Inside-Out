#packages and functions and loading data
pacman::p_load(tidyverse,rvest,tm,tidytext,ggplot2,quanteda,stm,dplyr,readability,mice)

stop <- rbind(tibble(text = stopwords("SMART")),"ill","im","yeah","dont","hey","back","lets")
nrc <- sentiments %>% filter(lexicon == "nrc") %>% select(-score, -lexicon)%>%
  filter(sentiment %in% c("joy","fear","disgust","anger","sadness"))

count_syllable <- function(ortho) {
	
	# Can add words to these lists of 2 syllable and 3 syllable 'exceptions'
	# Note that final -e is stripped before checking these lists!
	Specials.2 <- c('every', 'different', 'family', 'girl', 'girls', 'world', 'worlds', 'bein', 'being', 'something', 'mkay', 'mayb')
	Specials.3 <- c('anyon', 'everyon') # final -e is dropped	
	
	# Regular Expression exceptions
	# SubSyl - remove a syllable from the count for each sub-string match
	SubSyl <- c('cial',
		  	 	'tia',
		       	'cius',
		 	  	'cious',
			  	'giu',              # belgium!
			  	'ion',
			  	'iou',
			  	'^every',           # every, but also everything, everybody
			  	'sia$',
			  	'.ely$',            # absolutely! (but not ely!)
			  	'[^szaeiou]es$',    # fates, but not sasses
			  	'[^tdaeiou]ed$',    # trapped, but not fated
			  	'^ninet',           # nineteen, ninety
			  	'^awe'				# awesome
		  	   )

	# AddSyl - add a syllable to the count for each sub-string match
	AddSyl <- c('ia',
		  	 	'rie[rt]',
		 	 	'dien',
			 	'ieth',
			 	'iu',
			 	'io',
			 	'ii',
			 	'ienc',	      # ambience, science, ...
			 	'les?$',
			 	'[aeiouym][bp]l$',  # -Vble, plus -mble and -Vple
			 	'[aeiou]{3}',       # agreeable
			 	'ndl(ed)?$',        # handle, handled
			 	'mpl(ed)?$',	    # trample, trampled
				'^mc',				# McEnery
			 	'ism$',             # -isms
			 	'([^aeiouy])\\1l(ed)?$',  # middle twiddle battle bottle, etc.
			 	'[^l]lien',         # alien, salient [1]
			 	'^coa[dglx].',      # [2]
			 	'[^gq]ua[^aeiou]',  # i think this fixes more than it breaks
			 	'[sd]nt$',          # couldn't, didn't, hasn't, wasn't,...
			 	'\\wshes$',          # add one back for esh (since it's -'d)
			 	'\\wches$',          #  and for affricate (witches)
			 	'\\wges$',           #  and voiced (ages)
			 	'\\wces$',	      #  and sibilant 'c's (places)
			 	'\\w[aeiouy]ing[s]?$'   # vowels before -ing = hiatus
		  	   )
		  
	tot_syls <- 0
	ortho.l <- tolower(ortho)
	stripchars <- "[:'\\[\\]]"
	ortho.cl <- gsub(stripchars, "", ortho.l, perl=T)
	spacechars <- "[\\W_]" # replace other non-word chars with space
	ortho.cl <- gsub(spacechars, " ", ortho.cl, perl=T)
	ortho.vec <- unlist(strsplit(ortho.cl, " ", perl=T))
	ortho.vec <- ortho.vec[ortho.vec!=""]
	for (w in ortho.vec) {
		w <- gsub("e$", "", w, perl=T) # strip final -e
		syl <- 0
		# is word in the 2 syllable exception list?
		if (w %in% Specials.2) {
			syl <- 2
		
		# is word in the 3 syllable exception list?
		} else if (w %in% Specials.3) {
			syl <- 3
			
		# if not, than check the different parts...
		} else {
			for (pat in SubSyl) {
				if (length(grep(pat, w, perl=T))>=1) 
					syl <- syl - 1
			}
			for (pat in AddSyl) {
				if (length(grep(pat, w, perl=T))>=1) 
					syl <- syl + 1
			}
			if (nchar(w)==1) {
				syl <- 1
			} else {
				chnk <- unlist(strsplit(w, "[^aeiouy:]+"))
				chnk <- chnk[chnk!=""]
				syl <- syl + length(chnk)
				if (syl==0) syl <- 1
			}
		}
		tot_syls <- tot_syls + syl
	}
	tot_syls
}
quoter <-function(y,z){
 place <- quote.dat %>%
    mutate(row = row_number()) %>%
    filter(speaker == y & sentiment == z) %>%
    select(linenumber,n,row,text) %>%
    arrange(desc(n))
    print(place)
}


webpage <- read_html('http://transcripts.wikia.com/wiki/Inside_Out')
web_text <- html_nodes(webpage,'#mw-content-text') %>%
             html_text() %>%
  strsplit(split = "\n") %>%
  unlist() %>%
  .[. != ""]

webdat <- data.frame(web_text) %>% 
  mutate(web_text = trimws(str_replace(web_text, "\\[.*?\\]", ""))) %>%
  filter(web_text != "" & web_text != "Transcript Edit") %>% 
  separate(web_text,into = c("speaker","text"), sep=":")

webdat$text<- gsub("\\[[^\\]]*\\]", "", webdat$text, perl=TRUE);
webdat$text<- gsub("\\([^\\]]*\\)", "", webdat$text, perl=TRUE);
webdat$text <- gsub('"', '', webdat$text)       

text_cleanish<-webdat%>%
  filter(text != " ") %>%
  mutate(linenumber = row_number())

#####
#cleaning
text.dat <- text_cleanish %>% 
  as.tibble() %>%
  janitor::clean_names() %>%
  mutate(text = removePunctuation(as.character(text)),
         linenumber = row_number()) %>% 
  unnest_tokens(text, text) %>%
  anti_join(stop) %>%
  filter(speaker %in% c("Joy","Fear","Disgust","Anger","Sadness","Bing Bong")) %>%
  group_by(speaker) %>%
  mutate(speaker_count = n()) %>%
  ungroup()

text.dat %>%
  group_by(speaker) %>%
  count(speaker, sort = TRUE)

#####
#sentiment analysis first
sent.speaker <- text.dat %>% 
  filter(speaker %in% c("Joy","Fear","Disgust","Anger","Sadness","Bing Bong")) %>%
  inner_join(nrc, by = c("text" = "word")) %>%
  count(speaker, sentiment, speaker_count) %>%
  spread(sentiment, n) %>%
  mutate(total = anger + disgust + fear + joy + sadness,
         ratio_positive = round((joy)/total,2),
         total_emotions = joy + fear + sadness + anger + disgust,
         joy_percent = (joy/total_emotions)*100,
         fear_percent = (fear/total_emotions)*100,
         sadness_percent = ((sadness/total_emotions)*100)-.11,
         anger_percent = ((anger/total_emotions)*100)+.22,
         disgust_percent = ((disgust/total_emotions)*100)-.11) %>%
  arrange(desc(ratio_positive)) %>%
  select(speaker,joy,joy_percent,fear,fear_percent,sadness,sadness_percent,
         anger,anger_percent,disgust,disgust_percent,total,ratio_positive,speaker_count) %>%
  gather(key = sentiment, value = scores,-speaker,-total,-ratio_positive,
         -joy_percent,-fear_percent,-sadness_percent,-anger_percent,-disgust_percent,-speaker_count) %>%
  mutate(scores = round(scores,3))

#someone teach me how to do this better
sent.place <- sent.speaker %>%
  select(speaker,joy_percent,fear_percent,sadness_percent,disgust_percent,anger_percent) %>%
  gather(key=sentiment.1, value = percents, - speaker) %>%
  mutate(sentiment = case_when(sentiment.1 == "joy_percent" ~ "joy",
                               sentiment.1 == "fear_percent" ~ "fear",
                               sentiment.1 == "sadness_percent" ~ "sadness",
                               sentiment.1 == "disgust_percent" ~ "disgust",
                               sentiment.1 == "anger_percent" ~ "anger")) %>%
  distinct() %>%
  select(speaker,percents,sentiment)
         
sent.data <- left_join(sent.speaker,sent.place) %>%
  select(speaker,total,ratio_positive,sentiment,scores,percents,speaker_count)


#####
#gobbledygook
gobble_text <- text_cleanish %>%
  filter(speaker %in% c("Joy","Fear","Disgust","Anger","Sadness","Bing Bong")) %>%
  unnest_tokens(text,text, drop = FALSE) %>%
  mutate(row = row_number()) %>%
  left_join(nrc, by = c("text" = "word")) %>%
  rowwise() %>%
  mutate(n_syllables = (count_syllable(text))) %>%
  ungroup()

gobble_data <- left_join(gobble_text %>%
  group_by(speaker,sentiment) %>%
  summarise(n_text = n_distinct(text)),
  gobble_text %>%
  group_by(speaker,sentiment) %>%
  filter(n_syllables >= 3) %>%
  summarise(n_polysyllables = n())) %>%
  mutate(SMOG = 1.0430 * sqrt(30 * n_polysyllables/n_text) + 3.1291) %>%
  arrange(desc(speaker))%>% 
  mice(m = 50, maxit = 20, method = "pmm", seed = 42069) %>%
  complete() %>%
  na.omit() %>%
  arrange(desc(speaker))

#####
quote.dat <- text.dat %>%
  left_join(nrc, by = c("text" = "word")) %>%
  group_by(linenumber, sentiment,speaker) %>%
  count() %>%
  drop_na() %>%
  ungroup() %>%
  arrange(desc(n)) %>%
  left_join(text_cleanish, by = "linenumber") %>%
  mutate(speaker = speaker.x,
         row = row_number()) %>%
  select(linenumber,text,speaker,sentiment,n,row)


quoter("Sadness","sadness")

quote.joiner <- quote.dat %>%
  slice(c(38,160,267,150,376,
          104,5,147,156,6,
          64,36,41,362,184,
          140,226,29,43,295,
          15,62,336,312,58,
          130,201,117,182,401))

quoter.dat <- inner_join(quote.joiner,gobble_data)
inside.out.dat <- left_join(quoter.dat,sent.data)
write.csv(inside.out.dat,"inside_out.csv")

#####
#lexical 


#####
#sentence smog
sentence_dat <- text.dat %>% 
  as.tibble() %>%
  janitor::clean_names() %>%
  mutate(text = removePunctuation(as.character(text)),
         linenumber = row_number()) %>% 
  unnest_tokens(text, text) %>%
  filter(speaker %in% c("Joy","Fear","Disgust","Anger","Sadness","Bing Bong"))

sentence_smog <- text.dat %>%
  rowwise() %>%
  mutate(n_syllables = count_syllable(text)) %>%
  ungroup() %>%
  arrange(desc(n_syllables))%>%
  filter(speaker %in% c("Joy","Fear","Disgust","Anger","Sadness","Bing Bong"))

sentence_results <- sentence_smog %>%
  mutate(complexity = textstat_readability(text,"SMOG")) %>%
  arrange(desc(complexity))
  
#####
#Structural stuff
speaker_tf_idf <- text.dat %>%
  count(speaker, text, sort = TRUE) %>%
  bind_tf_idf(text, speaker, n) %>%
  arrange(-tf_idf) %>%
  group_by(speaker) %>%
  top_n(10) %>%
  ungroup() 

speaker_tf_idf %>%
    mutate(word = reorder_within(text, tf_idf, speaker)) %>%
    ggplot(aes(word, tf_idf, fill = speaker)) +
    geom_col(alpha = 0.8, show.legend = FALSE) +
    facet_wrap(~ speaker, scales = "free", ncol = 3) +
    scale_x_reordered() +
    coord_flip() +
    theme(strip.text=element_text(size=11)) +
    labs(x = NULL, y = "tf-idf",
         title = "Highest tf-idf words",
         subtitle = "Individual stories focus on different narrative elements")

inside_sparse <- text.dat %>%
  count(speaker,text, sort = TRUE) %>%
  cast_sparse (speaker,text,n)

topic_model <- stm(inside_sparse, K = 6, verbose = FALSE, init.type = "Spectral")
summary(topic_model)
td_inside <- tidy(topic_model)

td_inside %>%
    group_by(topic) %>%
    top_n(10, beta) %>%
    ungroup() %>%
    mutate(topic = paste0("Topic ", topic),
           term = reorder_within(term, beta, topic)) %>%
    ggplot(aes(term, beta, fill = as.factor(topic))) +
    geom_col(alpha = 0.8, show.legend = FALSE) +
    facet_wrap(~ topic, scales = "free_y") +
    coord_flip() +
    scale_x_reordered() +
    labs(x = NULL, y = expression(beta),
         title = "Highest word probabilities for each topic",
         subtitle = "Different words are associated with different topics")

#####
sent.join %>%
  filter(sentiment %in% c("joy","fear","disgust","anger","sadness")) %>% 
  count(text, sentiment) %>%
  group_by(sentiment) %>%
  top_n(10, n) %>%
  ungroup() %>%
  mutate(text = reorder(text, n)) %>%
  ggplot(aes(text, n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ sentiment, scales = "free") +
  coord_flip()
reorder_within <- function(x, by, within, fun = mean, sep = "___", ...) {
  new_x <- paste(x, within, sep = sep)
  stats::reorder(new_x, by, FUN = fun)
}
scale_x_reordered <- function(..., sep = "___") {
  reg <- paste0(sep, ".+$")
  ggplot2::scale_x_discrete(labels = function(x) gsub(reg, "", x), ...)
}
