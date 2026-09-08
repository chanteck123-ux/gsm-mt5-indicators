// This harness is independent of the embedded production implementation.
// All fixture lists below run OLD -> NEW, ending at the last CLOSED bar.
// Buffer 0 (live bar) is appended separately and must never affect a closed rule.
int g_file=INVALID_HANDLE;
int g_checks=0,g_failures=0,g_groups=0,g_pass_groups=0,g_before=0;
string g_group="";

void Record(const string message)
  {
   Print(message);
   if(g_file!=INVALID_HANDLE) FileWrite(g_file,message);
  }
void Group(const string name)
  {
   g_group=name;
   g_before=g_failures;
   g_groups++;
  }
void EndGroup()
  {
   bool ok=(g_failures==g_before);
   if(ok)g_pass_groups++;
   Record((ok?"PASS|":"FAIL|")+g_group+"|new_failures="+IntegerToString(g_failures-g_before));
  }
void Expect(const double actual,const double expected,const string label)
  {
   g_checks++;
   bool ok=expected==EMPTY_VALUE ? actual==EMPTY_VALUE : MathIsValidNumber(actual)&&actual!=EMPTY_VALUE&&MathAbs(actual-expected)<=1e-12;
   if(!ok)
     {
      g_failures++;
      Record("ASSERT_FAIL|"+g_group+"|"+label+"|expected="+(expected==EMPTY_VALUE?"EMPTY":DoubleToString(expected,12))+"|actual="+(actual==EMPTY_VALUE?"EMPTY":DoubleToString(actual,12)));
     }
  }
void ExpectTrue(const bool value,const string label){Expect(value?1.0:0.0,1.0,label);}

GSMRuleSettings Defaults()
  {
   GSMRuleSettings c;
   c.weak=20;c.trend=25;c.strong=40;c.epsilon=0;c.min_di_adx=25;
   c.confirm_bars=2;c.rise_comparisons=3;c.low_bars=10;c.cross_lookback=10;c.cross_min=3;c.use_min_di_adx=false;
   return c;
  }
void ParseClosed(const string csv,double &values[],const double live_value=99)
  {
   string parts[];
   int n=StringSplit(csv,StringGetCharacter(",",0),parts);
   ArrayResize(values,n+1);ArraySetAsSeries(values,true);
   values[0]=live_value;
   for(int i=0;i<n;i++) values[n-i]=parts[i]=="E"?EMPTY_VALUE:StringToDouble(parts[i]);
  }
void FillDI(const int count,const double value,double &values[])
  {
   ArrayResize(values,count);ArraySetAsSeries(values,true);ArrayInitialize(values,value);
  }
void Fixture(const string aa,const string pp,const string mm,const GSMRuleSettings &cfg,double &out[],const int shift=1)
  {
   double a[],p[],m[];ParseClosed(aa,a);
   if(pp=="")FillDI(ArraySize(a),30,p);else ParseClosed(pp,p);
   if(mm=="")FillDI(ArraySize(a),20,m);else ParseClosed(mm,m);
   ExpectTrue(ArraySize(a)==ArraySize(p)&&ArraySize(a)==ArraySize(m),"fixture has aligned A/P/M lengths");
   ArrayResize(out,12);GSMEvaluateRules(a,p,m,shift,ArraySize(a),cfg,out);
  }

void BoundaryTests()
  {
   GSMRuleSettings c=Defaults();double o[];
   Group("C01_market_state_exact_20_25_40");
   Fixture("19,20","","",c,o);Expect(o[0],1,"ADX=20 belongs to forming");Expect(o[3],0,"landing at 20 is not strict crossing");
   Fixture("24,25","","",c,o);Expect(o[0],2,"ADX=25 belongs to trend");Expect(o[4],0,"landing at 25 is not strict crossing");
   Fixture("39,40","","",c,o);Expect(o[0],2,"ADX=40 belongs to trend");
   Fixture("40,40.25","","",c,o);Expect(o[0],3,"ADX>40 belongs to strong");
   Fixture("20,19.75","","",c,o);Expect(o[0],0,"ADX<20 belongs to weak");
   Fixture("20,20.25","","",c,o);Expect(o[3],1,"previous exactly 20 allows crossing");
   Fixture("25,25.25","","",c,o);Expect(o[4],1,"previous exactly 25 allows crossing");
   EndGroup();

   Group("C02_two_threshold_events_same_bar");
   Fixture("19,26","","",c,o);Expect(o[3],1,"19 -> 26 retains CrossWeak");Expect(o[4],1,"19 -> 26 retains CrossTrend");
   EndGroup();

   Group("C03_high_and_rising_is_not_turn_down");
   Fixture("41,43,44","","",c,o);Expect(o[7],0,"41,43,44 has no high turn");Expect(o[2],1,"high rising slope remains positive");
   EndGroup();

   Group("C04_high_turn_confirm_bar_and_no_repeat");
   Fixture("40,41,43,42,41","","",c,o,3);Expect(o[7],0,"no signal at the 43 peak");
   Fixture("40,41,43,42,41","","",c,o,2);Expect(o[7],1,"signal is at the closed 42 confirmation");
   Fixture("40,41,43,42,41","","",c,o,1);Expect(o[7],0,"continued descent to 41 does not repeat");
   Fixture("39,40,39","","",c,o);Expect(o[7],0,"previous exactly 40 is not above high threshold");
   Fixture("41,43,43,42","","",c,o);Expect(o[7],1,"flat high plateau permits the subsequent first fall");
   EndGroup();

   Group("Custom_reference_thresholds_drive_states_and_events");
   c.weak=15;c.trend=22;c.strong=35;
   Fixture("14,23","","",c,o);Expect(o[0],2,"ADX23 is trend under custom threshold22");Expect(o[3],1,"14 -> 23 crosses custom weak15");Expect(o[4],1,"14 -> 23 crosses custom trend22");
   Fixture("14,15","","",c,o);Expect(o[0],1,"custom weak15 exact boundary");Expect(o[3],0,"custom weak strict cross excludes exact15");
   Fixture("21,22,22","","",c,o);Expect(o[8],1,"two bars at custom trend22 confirm");
   Fixture("34,35","","",c,o);Expect(o[0],2,"custom strong35 exact boundary remains trend");
   Fixture("35,36","","",c,o);Expect(o[0],3,"custom strong35 above boundary becomes strong");
   Fixture("35,37,36","","",c,o);Expect(o[7],1,"turn uses custom high35 even below default40");
   EndGroup();
  }

void DirectionTests()
  {
   GSMRuleSettings c=Defaults();double o[];
   Group("C05_bull_and_bear_DI_cross_with_rising_ADX");
   Fixture("19,21","10,30","20,20",c,o);Expect(o[5],1,"plus cross and rising ADX");Expect(o[6],0,"bull cross does not overwrite bear");Expect(o[1],1,"direction is bullish");
   Fixture("19,21","20,20","10,30",c,o);Expect(o[5],0,"bear cross does not overwrite bull");Expect(o[6],1,"minus cross and rising ADX");Expect(o[1],-1,"direction is bearish");
   Fixture("19,21","20,30","20,20",c,o);Expect(o[5],1,"previous DI equality permits strict bull departure");
   Fixture("19,21","20,20","20,30",c,o);Expect(o[6],1,"previous DI equality permits strict bear departure");
   EndGroup();

   Group("C06_DI_cross_while_ADX_falls_or_is_flat");
   Fixture("21,19","10,30","20,20",c,o);Expect(o[5],0,"ADX declining rejects bullish enhancement event");Expect(o[1],1,"direction still bullish independently");Expect(o[2],-1,"strength slope declines");
   Fixture("21,19","20,20","10,30",c,o);Expect(o[6],0,"ADX declining rejects bearish enhancement event");
   Fixture("19,19","10,30","20,20",c,o);Expect(o[5],0,"flat ADX is not enhancement");
   EndGroup();

   Group("C07_optional_minimum_ADX_filter");
   Fixture("17,18","10,30","20,20",c,o);Expect(o[5],1,"default filter off allows event below 20 and 25");Expect(o[0],0,"event does not reclassify weak environment");
   c.use_min_di_adx=true;Fixture("17,18","10,30","20,20",c,o);Expect(o[5],0,"filter on rejects ADX18");
   Fixture("24,25","10,30","20,20",c,o);Expect(o[5],1,"minimum filter includes exact 25");
   c.min_di_adx=18;Fixture("17,18","10,30","20,20",c,o);Expect(o[5],1,"custom filter threshold exact 18 accepted");
   EndGroup();
  }

void EntryTests()
  {
   GSMRuleSettings c=Defaults();double o[];
   Group("C08_confirm_and_rising_first_entry_sample_boundaries");
   Fixture("24,25","","",c,o);Expect(o[8],EMPTY_VALUE,"ConfirmBars2 entry requires current and previous complete windows");
   Fixture("24,25,25","","",c,o);Expect(o[8],1,"second at-or-above 25 creates first confirmed event");
   Fixture("23,24,25,25,26","","",c,o,2);Expect(o[8],1,"first event stays on second qualifying closed bar");
   Fixture("23,24,25,25,26","","",c,o,1);Expect(o[8],0,"third qualifying bar does not repeat");
   Fixture("10,11,12,13","","",c,o);Expect(o[9],EMPTY_VALUE,"3 comparisons state has 4 values but entry needs 5");
   Fixture("10,10,11,12,13","","",c,o);Expect(o[9],1,"third rising comparison creates first entry");Expect(o[0],0,"rising ADX13 still weak");
   Fixture("9,10,10,11,12,13,14","","",c,o,2);Expect(o[9],1,"rising event stays on 13 confirmation");
   Fixture("9,10,10,11,12,13,14","","",c,o,1);Expect(o[9],0,"fourth consecutive rise does not repeat");
   c.confirm_bars=1;Fixture("24,25","","",c,o);Expect(o[8],1,"ConfirmBars1 requires 2 values for entry");
   c.rise_comparisons=1;Fixture("10,10,11","","",c,o);Expect(o[9],1,"RiseComparisons1 requires 3 values for entry");
   EndGroup();

   Group("C09_raw_DI_choppy_equality_lookback_and_no_entanglement");
   Fixture("15,15,15,15,15,15,15,15,15,15,15,15","20,20,20,20,20,20,20,20,20,20,20,20","20,20,20,20,20,20,20,20,20,20,20,20",c,o);Expect(o[1],0,"continuous DI equality gives neutral direction");Expect(o[11],0,"DI equality is never raw crossover");
   Fixture("15,15,15,15,15,15,15,15,15,15,15","30,30,30,30,30,30,30,30,10,30,10","10,10,10,10,10,10,10,10,30,10,30",c,o);Expect(o[11],EMPTY_VALUE,"10 comparisons entry needs 12 values including prior state");
   Fixture("15,15,15,15,15,15,15,15,15,15,15,15","","",c,o);Expect(o[11],0,"low ADX without DI crossing is not choppy");
   c.use_min_di_adx=true;
   Fixture("18,18,18,18,18,18,18,18,18,17,16,15","30,30,30,30,30,30,30,30,30,10,30,10","10,10,10,10,10,10,10,10,10,30,10,30",c,o);Expect(o[11],1,"third raw cross enters choppy despite declining low ADX and minimum filter");Expect(o[6],0,"same bear cross fails rising ADX event");
   Fixture("18,18,18,18,18,18,18,18,18,17,16,15,14","30,30,30,30,30,30,30,30,30,10,30,10,30","10,10,10,10,10,10,10,10,10,30,10,30,10",c,o);Expect(o[11],0,"remaining choppy on next cross does not repeat entry");
   c.cross_lookback=3;c.cross_min=2;
   Fixture("22,22,22,20,19","30,10,30,10,30","10,30,10,30,10",c,o);Expect(o[11],1,"fall below weak threshold can enter existing raw DI entanglement");
   Fixture("22,22,22,19,20","30,10,30,10,30","10,30,10,30,10",c,o);Expect(o[11],0,"exact weak boundary is not low-ADX choppy");
   EndGroup();

   Group("LongLow_entry_strict_threshold_and_extra_history");
   c=Defaults();c.low_bars=3;
   Fixture("19,18,17","","",c,o);Expect(o[10],EMPTY_VALUE,"LowADXBars3 entry needs 4 values");
   Fixture("21,19,18,17","","",c,o);Expect(o[10],1,"third strict-low bar creates entry");
   Fixture("21,19,18,17,16","","",c,o);Expect(o[10],0,"fourth strict-low bar does not repeat");
   Fixture("21,19,20,17","","",c,o);Expect(o[10],0,"exact 20 interrupts strict-low sequence");
   c.low_bars=1;Fixture("20,19","","",c,o);Expect(o[10],1,"LowADXBars1 entry uses two values");
   EndGroup();
  }

void InvalidAndToleranceTests()
  {
   GSMRuleSettings c=Defaults();double o[];double a[],p[],m[];
   Group("C10_warmup_EMPTY_insufficient_samples_and_valid_zero");
   Fixture("0,0,0,0,0,0,0,0,0,0,0,0","0,0,0,0,0,0,0,0,0,0,0,0","0,0,0,0,0,0,0,0,0,0,0,0",c,o);
   for(int k=0;k<12;k++)Expect(o[k],0,"valid all-zero full-lookback output "+IntegerToString(k+3));
   Fixture("E,E,E","E,E,E","E,E,E",c,o);for(int k=0;k<12;k++)Expect(o[k],EMPTY_VALUE,"all-warmup output "+IntegerToString(k+3));
   Fixture("25","30","20",c,o);Expect(o[0],2,"one valid ADX supports market state");Expect(o[1],1,"one DI pair supports direction");for(int k=2;k<12;k++)Expect(o[k],EMPTY_VALUE,"one closed sample insufficient output "+IntegerToString(k+3));
   Fixture("E,19,26","10,10,30","20,20,20",c,o);Expect(o[3],1,"older EMPTY does not mask valid two-value CrossWeak");Expect(o[4],1,"older EMPTY does not mask valid two-value CrossTrend");Expect(o[7],EMPTY_VALUE,"high turn requires its older third value");Expect(o[8],EMPTY_VALUE,"confirm entry cannot substitute EMPTY previous window as false");
   Fixture("19,26","10,E","20,20",c,o);Expect(o[0],2,"ADX state independent of unavailable DI");Expect(o[1],EMPTY_VALUE,"missing DI makes direction unavailable");Expect(o[5],EMPTY_VALUE,"missing DI makes bull unavailable");
   ParseClosed("19,26",a);ParseClosed("10,30",p);ParseClosed("20,20",m);
   double badarg=2.0;a[1]=MathArcsin(badarg);ExpectTrue(!MathIsValidNumber(a[1]),"NaN fixture actually invalid");GSMEvaluateRules(a,p,m,1,ArraySize(a),c,o);Expect(o[0],EMPTY_VALUE,"NaN is not a market state");Expect(o[3],EMPTY_VALUE,"NaN is not no-cross zero");
   double huge=10000;a[1]=MathExp(huge);ExpectTrue(!MathIsValidNumber(a[1]),"infinity fixture actually invalid");GSMEvaluateRules(a,p,m,1,ArraySize(a),c,o);Expect(o[0],EMPTY_VALUE,"infinity is unavailable");
   EndGroup();

   Group("SlopeEpsilon_strict_comparisons_and_inclusive_prior_turn");
   c=Defaults();c.epsilon=0.5;
   Fixture("20,20.5","10,30","20,20",c,o);Expect(o[2],0,"difference exactly +epsilon is flat");Expect(o[5],0,"bull enhancement requires strict >epsilon");
   Fixture("20,19.5","","",c,o);Expect(o[2],0,"difference exactly -epsilon is flat");
   Fixture("20,20.75","10,30","20,20",c,o);Expect(o[2],1,"difference greater than epsilon strengthens");Expect(o[5],1,"strict rising crossover accepted");
   Fixture("20,19.25","","",c,o);Expect(o[2],-1,"difference less than negative epsilon weakens");
   Fixture("42.5,42,41","","",c,o);Expect(o[7],1,"previous slope equal to -epsilon permits new clear fall");
   Fixture("43,42,41","","",c,o);Expect(o[7],0,"already clear decline does not make another turn");
   Fixture("42,42,41.5","","",c,o);Expect(o[7],0,"current fall exactly epsilon is not turn");
   Fixture("10,10,10.5,11.5,12.5","","",c,o);Expect(o[9],0,"one comparison exactly epsilon breaks rising run");
   EndGroup();

   Group("C11_core_shift_zero_never_publishes_confirmed_outputs");
   c=Defaults();ParseClosed("40,41,43,42",a);ParseClosed("10,30,10,30",p);ParseClosed("30,10,30,10",m);
   for(int j=0;j<12;j++)
     {
      a[0]=(j%2==0?19:45);p[0]=(j%2==0?10:40);m[0]=(j%2==0?40:10);
      GSMEvaluateRules(a,p,m,0,ArraySize(a),c,o);
      for(int k=0;k<12;k++)Expect(o[k],EMPTY_VALUE,"live alternation "+IntegerToString(j)+" output "+IntegerToString(k+3));
      GSMEvaluateRules(a,p,m,1,ArraySize(a),c,o);Expect(o[7],1,"closed 42 turn unaffected by live threshold crossing");
     }
   Record("SCOPE|C11 above is production pure-rule shift-0 testing; native terminal live-buffer publication is tested separately.");
   EndGroup();
  }

void ReplayTests()
  {
   GSMRuleSettings c=Defaults();double a[],p[],m[],aa[],pp[],mm[],base[],got[];
   int n=256;ArrayResize(a,n+1);ArrayResize(p,n+1);ArrayResize(m,n+1);
   ArraySetAsSeries(a,true);ArraySetAsSeries(p,true);ArraySetAsSeries(m,true);
   a[0]=99;p[0]=99;m[0]=0;
   for(int old=0;old<n;old++)
     {
      int phase=old%64;
      a[n-old]=phase<=32?phase*1.5:(64-phase)*1.5;
      p[n-old]=old%3==0?30:10;m[n-old]=old%3==0?10:30;
      if(old<7){a[n-old]=EMPTY_VALUE;p[n-old]=EMPTY_VALUE;m[n-old]=EMPTY_VALUE;}
     }
   ArrayResize(base,12);ArrayResize(got,12);
   Group("Causal_prefix_replay_versus_full_history_all_12_outputs");
   for(int old=0;old<n;old++)
     {
      int shift=n-old;
      GSMEvaluateRules(a,p,m,shift,n+1,c,base);
      ArrayResize(aa,old+2);ArrayResize(pp,old+2);ArrayResize(mm,old+2);
      ArraySetAsSeries(aa,true);ArraySetAsSeries(pp,true);ArraySetAsSeries(mm,true);
      aa[0]=0;pp[0]=0;mm[0]=100;
      for(int prior=0;prior<=old;prior++){aa[old+1-prior]=a[n-prior];pp[old+1-prior]=p[n-prior];mm[old+1-prior]=m[n-prior];}
      GSMEvaluateRules(aa,pp,mm,1,old+2,c,got);
      for(int k=0;k<12;k++)Expect(got[k],base[k],"prefix bar="+IntegerToString(old)+" buffer="+IntegerToString(k+3));
     }
   EndGroup();

   Group("Future_perturbation_cannot_change_closed_historical_outputs");
   ArrayResize(aa,n+1);ArrayResize(pp,n+1);ArrayResize(mm,n+1);
   ArraySetAsSeries(aa,true);ArraySetAsSeries(pp,true);ArraySetAsSeries(mm,true);
   for(int shift=1;shift<=n;shift++)
     {
      for(int j=0;j<=n;j++){aa[j]=a[j];pp[j]=p[j];mm[j]=m[j];}
      for(int j=0;j<shift;j++){aa[j]=j%2==0?0:99;pp[j]=j%2==0?90:1;mm[j]=j%2==0?1:90;}
      GSMEvaluateRules(a,p,m,shift,n+1,c,base);GSMEvaluateRules(aa,pp,mm,shift,n+1,c,got);
      for(int k=0;k<12;k++)Expect(got[k],base[k],"future change shift="+IntegerToString(shift)+" buffer="+IntegerToString(k+3));
     }
   EndGroup();
  }

void OnStart()
  {
   g_file=FileOpen("GSM_ADX_Rules_results.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(g_file==INVALID_HANDLE){Print("FAIL|cannot create rule test report|error=",GetLastError());return;}
   Record("GSM ADX production-core native MQL5 rule tests");
   Record("RULE_BLOCK_SHA256="+RULE_BLOCK_SHA256);
   Record("TERMINAL_BUILD="+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD)));
   Record("SOURCE=hand-authored ADX/DI vectors and fixed 256-bar causal fixture; no account or order API calls.");
   BoundaryTests();DirectionTests();EntryTests();InvalidAndToleranceTests();ReplayTests();
   Record("SCOPE|C12 visual/alert switches and full iCustom publication are tested by native integration scripts, not inferred from this pure-rule test.");
   Record("OVERALL="+(g_failures==0?"PASS":"FAIL")+"|groups="+IntegerToString(g_groups)+"|passed_groups="+IntegerToString(g_pass_groups)+"|assertions="+IntegerToString(g_checks)+"|failures="+IntegerToString(g_failures));
   FileFlush(g_file);FileClose(g_file);
  }
