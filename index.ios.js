'use strict';

import { NativeModules, processColor } from 'react-native';

const RNCalendarEvents = NativeModules.RNCalendarEvents;

export default {

  authorizationStatus () {
    return RNCalendarEvents.authorizationStatus()
  },

  authorizeEventStore () {
    return RNCalendarEvents.authorizeEventStore()
  },

  fetchAllEvents (startDate, endDate, calendars = []) {
    return RNCalendarEvents.fetchAllEvents(startDate, endDate, calendars)
  },

  createCalendar (name, color) {
    return RNCalendarEvents.create(name, color)
  },

  deleteCalendarByName (name) {
    return RNCalendarEvents.deleteCalendarByName(name)
  },

  findCalendars () {
    return RNCalendarEvents.findCalendars();
  },

  saveCalendar (options = {}) {
    return RNCalendarEvents.saveCalendar({
      ...options,
      color: options.color ? processColor(options.color) : undefined,
    });
  },

  findEventById (id) {
    return RNCalendarEvents.findEventById(id);
  },

  saveEvent (title, details, options = {}) {
    return RNCalendarEvents.saveEvent(title, details, options)
  },

  removeEvent (id, options = {futureEvents: false}) {
    return RNCalendarEvents.removeEvent(id, options)
  },

  removeFutureEvents (id, options = {futureEvents: true}) {
    return RNCalendarEvents.removeEvent(id, options)
  }

}
