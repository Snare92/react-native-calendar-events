#import "RNCalendarEvents.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>
#import <EventKit/EventKit.h>

@interface RNCalendarEvents ()
@property (nonatomic, readonly) EKEventStore *eventStore;
@end

static NSString *const _id = @"id";
static NSString *const _calendarId = @"calendarId";
static NSString *const _title = @"title";
static NSString *const _location = @"location";
static NSString *const _startDate = @"startDate";
static NSString *const _endDate = @"endDate";
static NSString *const _allDay = @"allDay";
static NSString *const _notes = @"notes";
static NSString *const _url = @"url";
static NSString *const _alarms = @"alarms";
static NSString *const _recurrence = @"recurrence";
static NSString *const _recurrenceRule = @"recurrenceRule";
static NSString *const _occurrenceDate = @"occurrenceDate";
static NSString *const _isDetached = @"isDetached";
static NSString *const _availability = @"availability";
static NSString *const _attendees    = @"attendees";

@implementation RNCalendarEvents

- (NSString *)hexStringFromColor:(UIColor *)color {
    const CGFloat *components = CGColorGetComponents(color.CGColor);

    CGFloat r = components[0];
    CGFloat g = components[1];
    CGFloat b = components[2];

    return [NSString stringWithFormat:@"#%02lX%02lX%02lX",
            lroundf(r * 255),
            lroundf(g * 255),
            lroundf(b * 255)];
}

// Assumes input like "#00FF00" (#RRGGBB)
- (UIColor*) colorFromHexString:(NSString*) hexString {
  unsigned rgbValue = 0;
  NSScanner *scanner = [NSScanner scannerWithString:hexString];
  [scanner setScanLocation:1]; // bypass '#' character
  [scanner scanHexInt:&rgbValue];
  return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16) / 255.0 green:((rgbValue & 0xFF00) >> 8) / 255.0 blue:(rgbValue & 0xFF) / 255.0 alpha:1.0];
}

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

#pragma mark -
#pragma mark Event Store Initialize

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventStore = [[EKEventStore alloc] init];
    }
    return self;
}

#pragma mark -
#pragma mark Event Store Authorization

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (BOOL)isCalendarAccessGranted
{
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

    return status == EKAuthorizationStatusAuthorized;
}

#pragma mark -
#pragma mark Event Store Accessors

- (NSDictionary *)buildAndSaveEvent:(NSDictionary *)details options:(NSDictionary *)options
{
    EKEvent *calendarEvent = nil;
    NSString *calendarId = [RCTConvert NSString:details[_calendarId]];
    NSString *eventId = [RCTConvert NSString:details[_id]];
    NSString *title = [RCTConvert NSString:details[_title]];
    NSString *location = [RCTConvert NSString:details[_location]];
    NSDate *startDate = [RCTConvert NSDate:details[_startDate]];
    NSDate *endDate = [RCTConvert NSDate:details[_endDate]];
    NSNumber *allDay = [RCTConvert NSNumber:details[_allDay]];
    NSString *notes = [RCTConvert NSString:details[_notes]];
    NSString *url = [RCTConvert NSString:details[_url]];
    NSArray *alarms = [RCTConvert NSArray:details[_alarms]];
    NSString *recurrence = [RCTConvert NSString:details[_recurrence]];
    NSDictionary *recurrenceRule = [RCTConvert NSDictionary:details[_recurrenceRule]];
    NSString *availability = [RCTConvert NSString:details[_availability]];
    NSArray *attendees = [RCTConvert NSArray:details[_attendees]];

    if (eventId) {
        calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    } else {
        calendarEvent = [EKEvent eventWithEventStore:self.eventStore];
        calendarEvent.calendar = [self.eventStore defaultCalendarForNewEvents];
        calendarEvent.timeZone = [NSTimeZone defaultTimeZone];

        if (calendarId) {
            EKCalendar *calendar = [self.eventStore calendarWithIdentifier:calendarId];

            if (calendar) {
                calendarEvent.calendar = calendar;
            }
        }
    }

    if (title) {
        calendarEvent.title = title;
    }

    if (location) {
        calendarEvent.location = location;
    }

    if (startDate) {
        calendarEvent.startDate = startDate;
    }

    if (endDate) {
        calendarEvent.endDate = endDate;
    }

    if (allDay) {
        calendarEvent.allDay = [allDay boolValue];
    }

    if (notes) {
        calendarEvent.notes = notes;
    }

    if (alarms) {
        calendarEvent.alarms = [self createCalendarEventAlarms:alarms];
    }

    if (attendees) {
        [calendarEvent setValue:[self createCalendarEventAttendees:attendees] forKey:_attendees];
    }

    if (recurrence) {
        EKRecurrenceRule *rule = [self createRecurrenceRule:recurrence interval:0 occurrence:0 endDate:nil];
        if (rule) {
            calendarEvent.recurrenceRules = [NSArray arrayWithObject:rule];
        }
    }

    if (recurrenceRule) {
        NSString *frequency = [RCTConvert NSString:recurrenceRule[@"frequency"]];
        NSInteger interval = [RCTConvert NSInteger:recurrenceRule[@"interval"]];
        NSInteger occurrence = [RCTConvert NSInteger:recurrenceRule[@"occurrence"]];
        NSDate *endDate = [RCTConvert NSDate:recurrenceRule[@"endDate"]];

        EKRecurrenceRule *rule = [self createRecurrenceRule:frequency interval:interval occurrence:occurrence endDate:endDate];
        if (rule) {
            calendarEvent.recurrenceRules = [NSArray arrayWithObject:rule];
        } else {
            calendarEvent.recurrenceRules = nil;
        }
    }


    if (availability) {
        calendarEvent.availability = [self availablilityConstantMatchingString:availability];
    }

    NSURL *URL = [NSURL URLWithString:[url stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]];
    if (URL) {
        calendarEvent.URL = URL;
    }

    return [self saveEvent:calendarEvent options:options];
}

- (NSDictionary *)saveEvent:(EKEvent *)calendarEvent options:(NSDictionary *)options
{
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null], @"error": [NSNull null]}];
    NSDate *exceptionDate = [RCTConvert NSDate:options[@"exceptionDate"]];
    EKSpan eventSpan = EKSpanFutureEvents;

    if (exceptionDate) {
        calendarEvent.startDate = exceptionDate;
        eventSpan = EKSpanThisEvent;
    }

    NSError *error = nil;
    BOOL success = [self.eventStore saveEvent:calendarEvent span:eventSpan commit:YES error:&error];

    if (!success) {
        [response setValue:[error.userInfo valueForKey:@"NSLocalizedDescription"] forKey:@"error"];
    } else {
        [response setValue:calendarEvent.calendarItemIdentifier forKey:@"success"];
    }
    return [response copy];
}

#pragma mark -
#pragma mark Alarms

- (EKAlarm *)createCalendarEventAlarm:(NSDictionary *)alarm
{
    EKAlarm *calendarEventAlarm = nil;
    id alarmDate = [alarm valueForKey:@"date"];

    if ([alarmDate isKindOfClass:[NSString class]]) {
        calendarEventAlarm = [EKAlarm alarmWithAbsoluteDate:[RCTConvert NSDate:alarmDate]];
    } else if ([alarmDate isKindOfClass:[NSNumber class]]) {
        int minutes = [alarmDate intValue];
        calendarEventAlarm = [EKAlarm alarmWithRelativeOffset:(60 * minutes)];
    } else {
        calendarEventAlarm = [[EKAlarm alloc] init];
    }

    if ([alarm objectForKey:@"structuredLocation"] && [[alarm objectForKey:@"structuredLocation"] count]) {
        NSDictionary *locationOptions = [alarm valueForKey:@"structuredLocation"];
        NSDictionary *geo = [locationOptions valueForKey:@"coords"];
        CLLocation *geoLocation = [[CLLocation alloc] initWithLatitude:[[geo valueForKey:@"latitude"] doubleValue]
                                                             longitude:[[geo valueForKey:@"longitude"] doubleValue]];

        calendarEventAlarm.structuredLocation = [EKStructuredLocation locationWithTitle:[locationOptions valueForKey:@"title"]];
        calendarEventAlarm.structuredLocation.geoLocation = geoLocation;
        calendarEventAlarm.structuredLocation.radius = [[locationOptions valueForKey:@"radius"] doubleValue];

        if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"enter"]) {
            calendarEventAlarm.proximity = EKAlarmProximityEnter;
        } else if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"leave"]) {
            calendarEventAlarm.proximity = EKAlarmProximityLeave;
        } else {
            calendarEventAlarm.proximity = EKAlarmProximityNone;
        }
    }
    return calendarEventAlarm;
}

- (NSArray *)createCalendarEventAttendees:(NSArray *)attendees
{
    NSMutableArray *calendarEventAttendees = [[NSMutableArray alloc] init];

    for (NSDictionary *attendeeDict in attendees) {
        Class className = NSClassFromString(@"EKAttendee");
        NSString *url = [attendeeDict valueForKey:@"url"];
        NSString *fName = [attendeeDict valueForKey:@"firstName"];
        NSString *lName = [attendeeDict valueForKey:@"lastName"];
        id attendee = [className new];
        [attendee setValue:fName forKey:@"firstName"];
        [attendee setValue:lName forKey:@"lastName"];
        [attendee setValue:url forKey:@"emailAddress"];
        [calendarEventAttendees addObject:attendee];
    }
    return [calendarEventAttendees copy];
}

- (NSArray *)createCalendarEventAlarms:(NSArray *)alarms
{
    NSMutableArray *calendarEventAlarms = [[NSMutableArray alloc] init];
    for (NSDictionary *alarm in alarms) {
        if ([alarm count] && ([alarm valueForKey:@"date"] || [alarm objectForKey:@"structuredLocation"])) {
            EKAlarm *reminderAlarm = [self createCalendarEventAlarm:alarm];
            [calendarEventAlarms addObject:reminderAlarm];
        }
    }
    return [calendarEventAlarms copy];
}

- (void)addCalendarEventAlarm:(NSString *)eventId alarm:(NSDictionary *)alarm options:(NSDictionary *)options
{
    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    EKAlarm *calendarEventAlarm = [self createCalendarEventAlarm:alarm];
    [calendarEvent addAlarm:calendarEventAlarm];

    [self saveEvent:calendarEvent options:options];
}

- (void)addCalendarEventAlarms:(NSString *)eventId alarms:(NSArray *)alarms options:(NSDictionary *)options
{
    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    calendarEvent.alarms = [self createCalendarEventAlarms:alarms];

    [self saveEvent:calendarEvent options:options];
}

#pragma mark -
#pragma mark RecurrenceRules

-(EKRecurrenceFrequency)frequencyMatchingName:(NSString *)name
{
    EKRecurrenceFrequency recurrence = nil;

    if ([name isEqualToString:@"weekly"]) {
        recurrence = EKRecurrenceFrequencyWeekly;
    } else if ([name isEqualToString:@"monthly"]) {
        recurrence = EKRecurrenceFrequencyMonthly;
    } else if ([name isEqualToString:@"yearly"]) {
        recurrence = EKRecurrenceFrequencyYearly;
    } else if ([name isEqualToString:@"daily"]) {
        recurrence = EKRecurrenceFrequencyDaily;
    }
    return recurrence;
}

-(EKRecurrenceRule *)createRecurrenceRule:(NSString *)frequency interval:(NSInteger)interval occurrence:(NSInteger)occurrence endDate:(NSDate *)endDate
{
    EKRecurrenceRule *rule = nil;
    EKRecurrenceEnd *recurrenceEnd = nil;
    NSInteger recurrenceInterval = 1;
    NSArray *validFrequencyTypes = @[@"daily", @"weekly", @"monthly", @"yearly"];

    if (frequency && [validFrequencyTypes containsObject:frequency]) {

        if (endDate) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:endDate];
        } else if (occurrence && occurrence > 0) {
            recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithOccurrenceCount:occurrence];
        }

        if (interval > 1) {
            recurrenceInterval = interval;
        }

        rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:[self frequencyMatchingName:frequency]
                                                            interval:recurrenceInterval
                                                                 end:recurrenceEnd];
    }
    return rule;
}

-(NSString *)nameMatchingFrequency:(EKRecurrenceFrequency)frequency
{
    switch (frequency) {
        case EKRecurrenceFrequencyWeekly:
            return @"weekly";
        case EKRecurrenceFrequencyMonthly:
            return @"monthly";
        case EKRecurrenceFrequencyYearly:
            return @"yearly";
        case EKRecurrenceFrequencyDaily:
            return @"daily";
        default:
            return @"";
    }
}

#pragma mark -
#pragma mark Availability

- (NSMutableArray *)calendarSupportedAvailabilitiesFromMask:(EKCalendarEventAvailabilityMask)types
{
    NSMutableArray *availabilitiesStrings = [[NSMutableArray alloc] init];

    if(types & EKCalendarEventAvailabilityBusy) [availabilitiesStrings addObject:@"busy"];
    if(types & EKCalendarEventAvailabilityFree) [availabilitiesStrings addObject:@"free"];
    if(types & EKCalendarEventAvailabilityTentative) [availabilitiesStrings addObject:@"tentative"];
    if(types & EKCalendarEventAvailabilityUnavailable) [availabilitiesStrings addObject:@"unavailable"];

    return availabilitiesStrings;
}

- (NSString *)availabilityStringMatchingConstant:(EKEventAvailability)constant
{
    switch(constant) {
        case EKEventAvailabilityNotSupported:
            return @"notSupported";
        case EKEventAvailabilityBusy:
            return @"busy";
        case EKEventAvailabilityFree:
            return @"free";
        case EKEventAvailabilityTentative:
            return @"tentative";
        case EKEventAvailabilityUnavailable:
            return @"unavailable";
        default:
            return @"notSupported";
    }
}

- (EKEventAvailability)availablilityConstantMatchingString:(NSString *)string
{
    if([string isEqualToString:@"busy"]) {
        return EKEventAvailabilityBusy;
    }

    if([string isEqualToString:@"free"]) {
        return EKEventAvailabilityFree;
    }

    if([string isEqualToString:@"tentative"]) {
        return EKEventAvailabilityTentative;
    }

    if([string isEqualToString:@"unavailable"]) {
        return EKEventAvailabilityUnavailable;
    }

    return EKEventAvailabilityNotSupported;
}

#pragma mark -
#pragma mark Serializers

- (NSArray *)serializeCalendarEvents:(NSArray *)calendarEvents
{
    NSMutableArray *serializedCalendarEvents = [[NSMutableArray alloc] init];

    for (EKEvent *event in calendarEvents) {

        [serializedCalendarEvents addObject:[self serializeCalendarEvent:event]];
    }

    return [serializedCalendarEvents copy];
}

- (NSDictionary *)serializeCalendarEvent:(EKEvent *)event
{

    NSDictionary *emptyCalendarEvent = @{
                                         _title: @"",
                                         _location: @"",
                                         _startDate: @"",
                                         _endDate: @"",
                                         _allDay: @NO,
                                         _notes: @"",
                                         _url: @"",
                                         _alarms: [NSArray array],
                                         _attendees: [NSArray array],
                                         _recurrence: @"",
                                         _recurrenceRule: @{
                                                 @"frequency": @"",
                                                 @"interval": @"",
                                                 @"occurrence": @"",
                                                 @"endDate": @""
                                                 },
                                         _availability: @"",
                                         };

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z"];


    NSMutableDictionary *formedCalendarEvent = [NSMutableDictionary dictionaryWithDictionary:emptyCalendarEvent];

    if (event.calendarItemIdentifier) {
        [formedCalendarEvent setValue:event.calendarItemIdentifier forKey:_id];
    }

    if (event.calendar) {
        [formedCalendarEvent setValue:@{
                                        @"id": event.calendar.calendarIdentifier,
                                        @"title": event.calendar.title ? event.calendar.title : @"",
                                        @"source": event.calendar.source && event.calendar.source.title ? event.calendar.source.title : @"",
                                        @"allowsModifications": @(event.calendar.allowsContentModifications),
                                        @"allowedAvailabilities": [self calendarSupportedAvailabilitiesFromMask:event.calendar.supportedEventAvailabilities],
                                        @"color": [self hexStringFromColor:[UIColor colorWithCGColor:event.calendar.CGColor]]
                                        }
                               forKey:@"calendar"];
    }

    if (event.title) {
        [formedCalendarEvent setValue:event.title forKey:_title];
    }

    if (event.notes) {
        [formedCalendarEvent setValue:event.notes forKey:_notes];
    }

    if (event.URL) {
        [formedCalendarEvent setValue:[event.URL absoluteString] forKey:_url];
    }

    if (event.location) {
        [formedCalendarEvent setValue:event.location forKey:_location];
    }

    if (event.attendees) {
        NSMutableArray *attendees = [[NSMutableArray alloc] init];
        for (EKParticipant *attendee in event.attendees) {

            NSMutableDictionary *descriptionData = [NSMutableDictionary dictionary];
            for (NSString *pairString in [attendee.description componentsSeparatedByString:@";"])
            {
                NSArray *pair = [pairString componentsSeparatedByString:@"="];
                if ( [pair count] != 2)
                    continue;
                [descriptionData setObject:[[pair objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey:[[pair objectAtIndex:0]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            }

            NSMutableDictionary *formattedAttendee = [[NSMutableDictionary alloc] init];
            NSString *name = [descriptionData valueForKey:@"name"];
            NSString *email = [descriptionData valueForKey:@"email"];
            NSString *phone = [descriptionData valueForKey:@"phone"];

            if(email && ![email isEqualToString:@"(null)"]) {
                [formattedAttendee setValue:email forKey:@"email"];
            }
            else {
                [formattedAttendee setValue:@"" forKey:@"email"];
            }
            if(phone && ![phone isEqualToString:@"(null)"]) {
                [formattedAttendee setValue:phone forKey:@"phone"];
            }
            else {
                [formattedAttendee setValue:@"" forKey:@"phone"];
            }
            if(name && ![name isEqualToString:@"(null)"]) {
                [formattedAttendee setValue:name forKey:@"name"];
            }
            else {
                [formattedAttendee setValue:@"" forKey:@"name"];
            }
            [attendees addObject:formattedAttendee];
        }
        [formedCalendarEvent setValue:attendees forKey:_attendees];
    }
    if (event.hasAlarms) {
        NSMutableArray *alarms = [[NSMutableArray alloc] init];

        for (EKAlarm *alarm in event.alarms) {

            NSMutableDictionary *formattedAlarm = [[NSMutableDictionary alloc] init];
            NSString *alarmDate = nil;

            if (alarm.absoluteDate) {
                alarmDate = [dateFormatter stringFromDate:alarm.absoluteDate];
            } else if (alarm.relativeOffset) {
                NSDate *calendarEventStartDate = nil;
                if (event.startDate) {
                    calendarEventStartDate = event.startDate;
                } else {
                    calendarEventStartDate = [NSDate date];
                }
                alarmDate = [dateFormatter stringFromDate:[NSDate dateWithTimeInterval:alarm.relativeOffset
                                                                             sinceDate:calendarEventStartDate]];
            }
            [formattedAlarm setValue:alarmDate forKey:@"date"];

            if (alarm.structuredLocation) {
                NSString *proximity = nil;
                switch (alarm.proximity) {
                    case EKAlarmProximityEnter:
                        proximity = @"enter";
                        break;
                    case EKAlarmProximityLeave:
                        proximity = @"leave";
                        break;
                    default:
                        proximity = @"None";
                        break;
                }
                [formattedAlarm setValue:@{
                                           @"title": alarm.structuredLocation.title,
                                           @"proximity": proximity,
                                           @"radius": @(alarm.structuredLocation.radius),
                                           @"coords": @{
                                                   @"latitude": @(alarm.structuredLocation.geoLocation.coordinate.latitude),
                                                   @"longitude": @(alarm.structuredLocation.geoLocation.coordinate.longitude)
                                                   }}
                                  forKey:@"structuredLocation"];

            }
            [alarms addObject:formattedAlarm];
        }
        [formedCalendarEvent setValue:alarms forKey:_alarms];
    }

    if (event.startDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.startDate] forKey:_startDate];
    }

    if (event.endDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.endDate] forKey:_endDate];
    }

    if (event.occurrenceDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.occurrenceDate] forKey:_occurrenceDate];
    }

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.isDetached] forKey:_isDetached];

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.allDay] forKey:_allDay];

    if (event.hasRecurrenceRules) {
        EKRecurrenceRule *rule = [event.recurrenceRules objectAtIndex:0];
        NSString *frequencyType = [self nameMatchingFrequency:[rule frequency]];
        [formedCalendarEvent setValue:frequencyType forKey:_recurrence];

        NSMutableDictionary *recurrenceRule = [NSMutableDictionary dictionaryWithDictionary:@{@"frequency": frequencyType}];

        if ([rule interval]) {
            [recurrenceRule setValue:@([rule interval]) forKey:@"interval"];
        }

        if ([[rule recurrenceEnd] endDate]) {
            [recurrenceRule setValue:[dateFormatter stringFromDate:[[rule recurrenceEnd] endDate]] forKey:@"endDate"];
        }

        if ([[rule recurrenceEnd] occurrenceCount]) {
            [recurrenceRule setValue:@([[rule recurrenceEnd] occurrenceCount]) forKey:@"occurrence"];
        }

        [formedCalendarEvent setValue:recurrenceRule forKey:_recurrenceRule];
    }

    [formedCalendarEvent setValue:[self availabilityStringMatchingConstant:event.availability] forKey:_availability];

    return [formedCalendarEvent copy];
}

- (EKCalendar*) findEKCalendar: (NSString *)calendarName {
  NSArray<EKCalendar *> *calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];
  if (calendars != nil && calendars.count > 0) {
    for (EKCalendar *thisCalendar in calendars) {
      if ([thisCalendar.title isEqualToString:calendarName]) {
        return thisCalendar;
      }
      if ([thisCalendar.calendarIdentifier isEqualToString:calendarName]) {
        return thisCalendar;
      }
    }
  }
  return nil;
}

#pragma mark -
#pragma mark RCT Exports

RCT_EXPORT_METHOD(authorizationStatus:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *status;
    EKAuthorizationStatus authStatus = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

    switch (authStatus) {
        case EKAuthorizationStatusDenied:
            status = @"denied";
            break;
        case EKAuthorizationStatusRestricted:
            status = @"restricted";
            break;
        case EKAuthorizationStatusAuthorized:
            status = @"authorized";
            break;
        default:
            status = @"undetermined";
            break;
    }

    resolve(status);
}

RCT_EXPORT_METHOD(authorizeEventStore:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
        NSString *status = granted ? @"authorized" : @"denied";
        if (!error) {
            resolve(status);
        } else {
            reject(@"error", @"authorization request error", error);
        }
    }];
}

RCT_EXPORT_METHOD(create:(NSString *)aTitle hexColor:(NSString *)hexColor resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{

    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }
    // if Calendar already Exists don't create it

    NSArray* calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];

    if (!calendars) {
        reject(@"error", @"error accessing calendars", nil);
        return;
    }

    for (EKCalendar *calendar in calendars) {
        if([calendar.title isEqualToString:aTitle]) {
            resolve(@"calendar already exists");
            return;
        }
    }

    // If the user has iCloud enabled and the Calendar sync option is also enabled within the iCloud
    // settings, the calendar created here MUST be created as an iCloud calendar. If it's created
    // as a local calendar it won't show up in the system's calendar list.

    // If the user doesn't have iCloud enabled, then we can go ahead and create a local calendar.


    EKSource *theSource;

    // First: Check if the user has an iCloud source set-up.
    for (EKSource *source in self.eventStore.sources) {
        if (source.sourceType == EKSourceTypeCalDAV && [source.title isEqualToString:@"iCloud"]) {
            theSource = source;
            break;
        }
    }

    // Second: If no iCloud source is set-up / utilised, then fall back and use the local source.
    if (theSource == nil) {
        for (EKSource *source in self.eventStore.sources) {
            if (source.sourceType == EKSourceTypeLocal)
            {
                theSource = source;
                break;
            }
        }
    }

    // If there is no local source and no iCloud source, we're unable to create a custom calendar.
    if (theSource == nil) {
        return reject(@"error", @"theSource is nil", nil);
    }

    // Create a custom calendar that will be responsible for holding event data.
    EKCalendar *calendar = [EKCalendar calendarForEntityType:EKEntityTypeEvent eventStore:self.eventStore];

    calendar.source = theSource;
    calendar.title = aTitle;

    if (hexColor != (id)[NSNull null]) {
        UIColor *theColor = [self colorFromHexString:hexColor];
        calendar.CGColor = theColor.CGColor;
    }

    // Save the calendar to the |EKEventStore| object.
    BOOL result = [self.eventStore saveCalendar:calendar commit:YES error:nil];

    // When the calendar is saved, the UUID is generated and we're able to store this value (if required).
    NSString *calendarID = calendar.calendarIdentifier;

    return resolve(calendarID);
}

RCT_EXPORT_METHOD(deleteCalendarByName:(NSString *)aTitle resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{

    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    EKCalendar *thisCalendar = [self findEKCalendar:aTitle];

    if (thisCalendar == nil) {
        resolve(@"calendar not found");
        return;
    }

    NSError *error;
    [self.eventStore removeCalendar:thisCalendar commit:YES error:&error];

    if (error) {
        reject(@"error", @"error in deleting calendar", nil);
        return;
    }

    resolve(@"calendar deleted");
    return;
}

RCT_EXPORT_METHOD(findCalendars:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    NSArray* calendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];

    if (!calendars) {
        reject(@"error", @"error finding calendars", nil);
    } else {
        NSMutableArray *eventCalendars = [[NSMutableArray alloc] init];
        for (EKCalendar *calendar in calendars) {
            [eventCalendars addObject:@{
                                        @"id": calendar.calendarIdentifier,
                                        @"title": calendar.title ? calendar.title : @"",
                                        @"allowsModifications": @(calendar.allowsContentModifications),
                                        @"source": calendar.source && calendar.source.title ? calendar.source.title : @"",
                                        @"allowedAvailabilities": [self calendarSupportedAvailabilitiesFromMask:calendar.supportedEventAvailabilities],
                                        @"color": [self hexStringFromColor:[UIColor colorWithCGColor:calendar.CGColor]]
                                        }];
        }
        resolve(eventCalendars);
    }
}

RCT_EXPORT_METHOD(fetchAllEvents:(NSDate *)startDate endDate:(NSDate *)endDate calendars:(NSArray *)calendars resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    NSMutableArray *eventCalendars;

    if (calendars.count) {
        eventCalendars = [[NSMutableArray alloc] init];
        NSArray *deviceCalendars = [self.eventStore calendarsForEntityType:EKEntityTypeEvent];

        for (EKCalendar *calendar in deviceCalendars) {
            if ([calendars containsObject:calendar.calendarIdentifier]) {
                [eventCalendars addObject:calendar];
            }
        }
    }

    NSPredicate *predicate = [self.eventStore predicateForEventsWithStartDate:startDate
                                                                      endDate:endDate
                                                                    calendars:eventCalendars];

    __weak RNCalendarEvents *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RNCalendarEvents *strongSelf = weakSelf;
        NSArray *calendarEvents = [[strongSelf.eventStore eventsMatchingPredicate:predicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
        if (calendarEvents) {
            resolve([strongSelf serializeCalendarEvents:calendarEvents]);
        } else if (calendarEvents == nil) {
            resolve(@[]);
        } else {
            reject(@"error", @"calendar event request error", nil);
        }
    });
}

RCT_EXPORT_METHOD(findEventById:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    __weak RNCalendarEvents *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RNCalendarEvents *strongSelf = weakSelf;

        EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
        if (calendarEvent) {
            resolve([strongSelf serializeCalendarEvent:calendarEvent]);
        } else {
            reject(@"error", @"error finding event", nil);
        }
    });
}

RCT_EXPORT_METHOD(saveEvent:(NSString *)title
                  settings:(NSDictionary *)settings
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    NSMutableDictionary *details = [NSMutableDictionary dictionaryWithDictionary:settings];
    [details setValue:title forKey:_title];

    __weak RNCalendarEvents *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RNCalendarEvents *strongSelf = weakSelf;

        NSDictionary *response = [strongSelf buildAndSaveEvent:details options:options];

        if ([response valueForKey:@"success"] != [NSNull null]) {
            resolve([response valueForKey:@"success"]);
        } else {
            reject(@"error", [response valueForKey:@"error"], nil);
        }
    });
}

RCT_EXPORT_METHOD(removeEvent:(NSString *)eventId options:(NSDictionary *)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    if (![self isCalendarAccessGranted]) {
        reject(@"error", @"unauthorized to access calendar", nil);
        return;
    }

    Boolean futureEvents = [RCTConvert BOOL:options[@"futureEvents"]];
    NSDate *exceptionDate = [RCTConvert NSDate:options[@"exceptionDate"]];

    if (exceptionDate) {
        NSPredicate *predicate = [self.eventStore predicateForEventsWithStartDate:exceptionDate
                                                                          endDate:[NSDate distantFuture]
                                                                        calendars:nil];
        __weak RNCalendarEvents *weakSelf = self;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            RNCalendarEvents *strongSelf = weakSelf;
            NSArray *calendarEvents = [strongSelf.eventStore eventsMatchingPredicate:predicate];
            EKEvent *eventInstance;
            BOOL success;

            for (EKEvent *event in calendarEvents) {
                if ([event.calendarItemIdentifier isEqualToString:eventId] && [event.startDate isEqualToDate:exceptionDate]) {
                    eventInstance = event;
                    break;
                }
            }

            if (eventInstance) {
                NSError *error = nil;
                EKSpan eventSpan = EKSpanThisEvent;

                if (futureEvents) {
                    eventSpan = EKSpanFutureEvents;
                }

                success = [strongSelf.eventStore removeEvent:eventInstance span:eventSpan commit:YES error:&error];
                if (error) {
                    return reject(@"error", [error.userInfo valueForKey:@"NSLocalizedDescription"], nil);
                }
            } else {
                return reject(@"error", @"No event found.", nil);
            }

            return resolve(@(success));
        });
    } else {
        EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
        NSError *error = nil;
        EKSpan eventSpan = EKSpanThisEvent;

        if (futureEvents) {
            eventSpan = EKSpanFutureEvents;
        }

        BOOL success = [self.eventStore removeEvent:calendarEvent span:eventSpan commit:YES error:&error];
        if (error) {
            return reject(@"error", [error.userInfo valueForKey:@"NSLocalizedDescription"], nil);
        }
        return resolve(@(success));
    }
}

@end

