const std = @import("std");

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectFmt = std.testing.expectFmt;

pub const Unit = enum {
    years,
    months,
    days,
    hours,
    minutes,
    seconds,
    milliseconds,
    microseconds,
    nanoseconds,
};

pub const Weekday = enum {
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,
    sunday,

    pub inline fn add(weekday: Weekday, days: anytype) Weekday {
        return @intToEnum(Weekday, @mod(@enumToInt(weekday) + @intCast(i8, @rem(days, 7)), 7));
    }
};

pub const WeekDate = struct {
    year: i64,
    week: u6,
    day: Weekday,

    pub fn format(
        week_date: WeekDate,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (week_date.year > 9999) {
            try writer.writeByte('+');
        } else if (week_date.year < 0) {
            try writer.writeByte('-');
        }
        try writer.print("{d:0>4}-W{d:0>2}-{d}", .{
            std.math.absCast(week_date.year),
            week_date.week,
            @as(u8, @enumToInt(week_date.day)) + 1,
        });
    }
};

pub const Date = struct {
    year: i64,
    month: u4,
    day: u5,

    /// Initialize a date given `year`, `month`, and `day`.
    ///
    /// An error will be emitted if `month` is not in the range `1...12` or
    /// `day` is not in the range applicable for `month` in `year`.
    pub fn init(year: i64, month: u4, day: u5) !Date {
        if (month < 1 or month > 12) return error.InvalidMonth;
        const result = Date{
            .year = year,
            .month = month,
            .day = day,
        };
        if (day < 1 or day > result.daysInMonth()) return error.InvalidDay;
        return result;
    }

    /// Initialize a date given `year`, `month`, and `day`.
    ///
    /// Be very careful with calling this function with variable input for
    /// `month` and/or `day`, as dates like February 29th may or may not exist
    /// within the provided `year`. Use `init()` to catch that sort of error.
    pub fn initUnchecked(year: i64, month: u4, day: u5) Date {
        std.debug.assert(month >= 1 and month <= 12); // Month must be in the range `1...12`.
        const result = Date{
            .year = year,
            .month = month,
            .day = day,
        };
        std.debug.assert(result.day >= 1 and result.day <= result.daysInMonth());
        return result;
    }

    /// Initialize a date from a 0-indexed `day` of `year`.
    ///
    /// This is the inverse operation of `dayOfYear()`. An error will be returned
    /// if the `day` is out of range for `year` (e.g. 365 in a non-leap year).
    pub fn fromDayOfYear(year: i64, day: u9) !Date {
        var result = Date{
            .year = year,
            .month = 1,
            .day = 1,
        };
        if (day < 31) {
            result.day = @intCast(u5, day + 1);
            return result;
        }

        const january_to_march = @as(u9, 31 + 28) + @boolToInt(result.isLeapYear());
        if (day < january_to_march) {
            result.month = 2;
            result.day = @intCast(u5, day - 31 + 1);
            return result;
        }

        const days_from_march_1st = day - january_to_march;
        switch (days_from_march_1st) {
            0...30 => {
                result.month = 3;
                result.day = @intCast(u5, days_from_march_1st + 1);
            },
            31...60 => {
                result.month = 4;
                result.day = @intCast(u5, days_from_march_1st - 31 + 1);
            },
            61...91 => {
                result.month = 5;
                result.day = @intCast(u5, days_from_march_1st - 61 + 1);
            },
            92...121 => {
                result.month = 6;
                result.day = @intCast(u5, days_from_march_1st - 92 + 1);
            },
            122...152 => {
                result.month = 7;
                result.day = @intCast(u5, days_from_march_1st - 122 + 1);
            },
            153...183 => {
                result.month = 8;
                result.day = @intCast(u5, days_from_march_1st - 153 + 1);
            },
            184...213 => {
                result.month = 9;
                result.day = @intCast(u5, days_from_march_1st - 184 + 1);
            },
            214...244 => {
                result.month = 10;
                result.day = @intCast(u5, days_from_march_1st - 214 + 1);
            },
            245...274 => {
                result.month = 11;
                result.day = @intCast(u5, days_from_march_1st - 245 + 1);
            },
            275...305 => {
                result.month = 12;
                result.day = @intCast(u5, days_from_march_1st - 275 + 1);
            },
            else => return error.Overflow, // Year does not have this many days.
        }

        return result;
    }

    /// Initialize a date from the `weekday` of the 1-indexed `week` in `year`.
    ///
    /// Week numbers can range from 1 through 52 or 53, depending on the year.
    /// See https://en.wikipedia.org/wiki/ISO_8601#Week_dates for more information.
    ///
    /// This is the inverse operation of `weekDate()`. An error be returned if
    /// `week` is out of range for `year`.
    pub fn fromWeekDate(year: i64, week: u6, weekday: Weekday) !Date {
        const weeks_in_year = initUnchecked(year, 12, 28).weekDate().week;
        if (week < 1) return error.Overflow; // Week dates are 1-indexed.
        if (week > weeks_in_year) return error.Overflow; // Year does not have this many weeks.

        const jan1_index = initUnchecked(year, 1, 1).dayIndex();
        const jan1_weekday = @intToEnum(Weekday, @mod(jan1_index - 2, 7));
        const this_week_01 = switch (jan1_weekday) {
            .monday => jan1_index,
            .tuesday => jan1_index - 1,
            .wednesday => jan1_index - 2,
            .thursday => jan1_index - 3,
            .friday => jan1_index + 3,
            .saturday => jan1_index + 2,
            .sunday => jan1_index + 1,
        };

        const day_offset = @as(u9, week - 1) * 7 + @enumToInt(weekday);
        return fromDayIndex(this_week_01 + day_offset);
    }

    /// Initialize a date from the number of days since `0000-01-01`.
    ///
    /// This is the inverse operation of `dayIndex()`. 
    pub fn fromDayIndex(day_index: i128) Date {
        const period_index = @divFloor(day_index, days_in_400_years);
        const periodic_day_index = @intCast(u32, @mod(day_index, days_in_400_years));

        var fake_day_index = periodic_day_index;
        if (periodic_day_index >= year_301_january_1st) {
            fake_day_index += 3;
        } else if (periodic_day_index >= year_201_january_1st) {
            fake_day_index += 2;
        } else if (periodic_day_index >= year_101_january_1st) {
            fake_day_index += 1;
        }

        const four_year_day_index = fake_day_index % days_in_4_years;
        var periodic_year_index = (fake_day_index / days_in_4_years) * 4;
        var day_of_year: u9 = 0;

        switch (four_year_day_index) {
            0...365 => {
                day_of_year = @intCast(u9, four_year_day_index);
            },
            366...730 => {
                periodic_year_index += 1;
                day_of_year = @intCast(u9, four_year_day_index - 366);
            },
            731...1095 => {
                periodic_year_index += 2;
                day_of_year = @intCast(u9, four_year_day_index - 731);
            },
            1096...1460 => {
                periodic_year_index += 3;
                day_of_year = @intCast(u9, four_year_day_index - 1096);
            },
            else => unreachable, // All possible results for `x % 1461` are handled.
        }

        const year = period_index * 400 + periodic_year_index;
        if (std.math.cast(i64, year)) |year_| {
            return fromDayOfYear(year_, day_of_year) catch unreachable;
        } else if (year < std.math.minInt(i64)) {
            return comptime initUnchecked(std.math.minInt(i64), 1, 1); 
        } else if (year > std.math.maxInt(i64)) {
            return comptime initUnchecked(std.math.maxInt(i64), 12, 31);
        } else unreachable;
    }

    pub fn add(date: Date, comptime unit: Unit, amount: i128) Date {
        var date_time = DateTime.init(date, Time.midnight, .utc);
        date_time.addToSelf(unit, amount);
        return date_time.date();
    }

    pub fn addToSelf(date: *Date, comptime unit: Unit, amount: i128) void {
        date.* = date.add(unit, amount);
    }

    /// Whether the current year is a leap year or not.
    pub fn isLeapYear(date: Date) bool {
        // ISO 8601 uses astronomical years, which has year 0 and negative years.
        // Therefore, this implementation works for both C.E. and B.C.E. dates.
        if (@mod(date.year, 400) == 0) return true;
        if (@mod(date.year, 100) == 0) return false;
        if (@mod(date.year, 4) == 0) return true;
        return false;
    }

    /// The number of days in the current month.
    pub fn daysInMonth(date: Date) u5 {
        return switch (date.month) {
            1 => 31, // January
            2 => @as(u5, 28) + @boolToInt(date.isLeapYear()), // February
            3 => 31, // March
            4 => 30, // April
            5 => 31, // May
            6 => 30, // June
            7 => 31, // July
            8 => 31, // August
            9 => 30, // September
            10 => 31, // October
            11 => 30, // November
            12 => 31, // December
            else => unreachable, // `Date` month is out of range.
        };
    }

    /// The number of days in the current year.
    pub fn daysInYear(date: Date) u9 {
        return @as(u9, 365) + @boolToInt(date.isLeapYear());
    }

    /// 0-indexed day of year (January 1st is day 0, February 1st is day 31).
    pub fn dayOfYear(date: Date) u9 {
        const day_of_month: u9 = date.day - 1;
        const january_to_march = @as(u9, 31 + 28) + @boolToInt(date.isLeapYear());
        return switch (date.month) {
            1 => day_of_month,
            2 => day_of_month + 31,
            3 => day_of_month + january_to_march,
            4 => day_of_month + january_to_march + 31,
            5 => day_of_month + january_to_march + 31 + 30,
            6 => day_of_month + january_to_march + 31 + 30 + 31,
            7 => day_of_month + january_to_march + 31 + 30 + 31 + 30,
            8 => day_of_month + january_to_march + 31 + 30 + 31 + 30 + 31,
            9 => day_of_month + january_to_march + 31 + 30 + 31 + 30 + 31 + 31,
            10 => day_of_month + january_to_march + 31 + 30 + 31 + 30 + 31 + 31 + 30,
            11 => day_of_month + january_to_march + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31,
            12 => day_of_month + january_to_march + 31 + 30 + 31 + 30 + 31 + 31 + 30 + 31 + 30,
            else => unreachable, // `Date` month is out of range.
        };
    }

    pub fn dayIndex(date: Date) i128 {
        const day_of_year: u32 = date.dayOfYear();
        const period_index = @divFloor(date.year, 400);
        const periodic_year_index = @intCast(u32, @mod(date.year, 400));

        const four_year_day_index = switch (periodic_year_index % 4) {
            0 => day_of_year,
            1 => day_of_year + 366,
            2 => day_of_year + 731,
            3 => day_of_year + 1096,
            else => unreachable, // All possible results for `x % 4` are handled.
        };

        const fake_day_index = (periodic_year_index / 4) * days_in_4_years + four_year_day_index;
        var periodic_day_index = fake_day_index;
        if (periodic_year_index >= 301) {
            periodic_day_index -= 3;
        } else if (periodic_year_index >= 201) {
            periodic_day_index -= 2;
        } else if (periodic_year_index >= 101) {
            periodic_day_index -= 1;
        }

        return @as(i128, period_index) * days_in_400_years + periodic_day_index;
    }

    pub fn weekDate(date: Date) WeekDate {
        const jan1 = initUnchecked(date.year, 1, 1);
        const jan1_index = jan1.dayIndex();
        const jan1_weekday = @intToEnum(Weekday, @mod(jan1_index - 2, 7));
        const this_week_01 = switch (jan1_weekday) {
            .monday => jan1_index,
            .tuesday => jan1_index - 1,
            .wednesday => jan1_index - 2,
            .thursday => jan1_index - 3,
            .friday => jan1_index + 3,
            .saturday => jan1_index + 2,
            .sunday => jan1_index + 1,
        };

        const day_index = jan1_index + date.dayOfYear();
        const weekday = @intToEnum(Weekday, @mod(day_index - 2, 7));
        if (day_index < this_week_01) {
            const last_dec28 = initUnchecked(date.year -| 1, 12, 28);
            const last_dec28_week_date = last_dec28.weekDate();
            return .{
                .year = last_dec28_week_date.year,
                .week = last_dec28_week_date.week,
                .day = weekday,
            };
        }

        const dec28 = initUnchecked(date.year, 12, 28);
        const dec28_index = jan1_index + dec28.dayOfYear();
        const dec28_weekday = @intToEnum(Weekday, @mod(dec28_index - 2, 7));
        const next_week_01 = dec28_index + 7 - @enumToInt(dec28_weekday);

        if (day_index >= next_week_01) {
            return .{
                .year = date.year +| 1,
                .week = 1,
                .day = weekday,
            };
        }

        return .{
            .year = date.year,
            .week = @intCast(u6, @intCast(u9, day_index - this_week_01) / 7 + 1),
            .day = weekday,
        };
    }

    pub fn dayOfWeek(date: Date) Weekday {
        return @intToEnum(Weekday, @mod(date.dayIndex() - 2, 7));
    }

    pub fn format(
        date: Date,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        if (date.year > 9999) {
            try writer.writeByte('+');
        } else if (date.year < 0) {
            try writer.writeByte('-');
        }
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{
            std.math.absCast(date.year),
            date.month,
            date.day,
        });
    }

    pub fn parse(buf: []const u8) !Date {
        const parser = try DateTimeParser.parse(.date, buf);
        return parseImpl(parser);
    }

    fn parseImpl(parser: DateTimeParser) !Date {
        const year_buf = parser.string(parser.year.?);
        const year = try std.fmt.parseInt(i64, year_buf, 10);

        switch (parser.date_type.?) {
            .calendar => {
                const month_buf = parser.string(parser.month.?);
                const month = try std.fmt.parseInt(u4, month_buf, 10);

                const day_buf = parser.string(parser.day.?);
                const day = try std.fmt.parseInt(u5, day_buf, 10);

                return Date.init(year, month, day);
            },
            .ordinal => {
                const day_buf = parser.string(parser.day.?);
                const day = try std.fmt.parseInt(u9, day_buf, 10);

                if (day < 1) return error.Overflow;

                return Date.fromDayOfYear(year, day - 1);
            },
            .week => {
                const week_buf = parser.string(parser.week.?);
                const week = try std.fmt.parseInt(u6, week_buf, 10);

                const day_buf = parser.string(parser.day.?);
                const day = try std.fmt.parseInt(u4, day_buf, 10);

                if (day < 1 or day > 7) return error.Overflow;

                return Date.fromWeekDate(year, week, @intToEnum(Weekday, day - 1));
            },
        }
    }

    pub const unix_epoch = initUnchecked(1970, 1, 1);
};

pub const Time = struct {
    hour: u5,
    minute: u6,
    second: u6,
    nanosecond: u30,

    pub fn init(hour: u5, minute: u6, second: u6, nanosecond: u30) Time {
        std.debug.assert(hour < 24); // Hour must be in the range `0...23`.
        std.debug.assert(minute < 60); // Minute must be in the range `0...59`.
        std.debug.assert(second <= 60); // Second must be in the range `0...60`.
        std.debug.assert(nanosecond < std.time.ns_per_s); // Nanosecond must be in the range `0...999_999_999`.
        return .{
            .hour = hour,
            .minute = minute,
            .second = second,
            .nanosecond = nanosecond,
        };
    }

    pub fn format(
        time: Time,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{
            time.hour,
            time.minute,
            time.second,
        });

        if (time.nanosecond == 0 or (options.precision != null and options.precision.? == 0)) return;

        var buf: [9]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{d:0>9}", .{ time.nanosecond }) catch return;

        const precision = options.precision orelse (
            std.mem.lastIndexOfAny(u8, &buf, "123456789").? + 1
        );

        try writer.print(".{s}", .{ buf[0..@min(precision, buf.len)] });
    }

    pub fn parse(buf: []const u8) !Time {
        const parser = try DateTimeParser.parse(.time, buf);
        return (try parseImpl(parser)).?;
    }

    fn parseImpl(parser: DateTimeParser) !?Time {
        const hour_buf = parser.string(parser.hour.?);
        const hour = try std.fmt.parseInt(u5, hour_buf, 10);

        const minute = if (parser.minute) |minute_span|
            try std.fmt.parseInt(u6, parser.string(minute_span), 10)
        else
            0;

        const second = if (parser.second) |second_span|
            try std.fmt.parseInt(u6, parser.string(second_span), 10)
        else
            0;

        const nanosecond = if (parser.fraction) |fraction_span| blk: {
            const fraction_buf = parser.string(fraction_span);
            const relevant_digits = fraction_buf[0..@min(fraction_buf.len, 9)];
            var fraction = std.fmt.parseUnsigned(u30, relevant_digits, 10) catch unreachable;
            for (0..(9 - relevant_digits.len)) |_| {
                fraction *= 10;
            }
            break :blk fraction;
        } else 0;

        if (parser.mode == .date_time and hour == 24 and minute == 0 and second == 0 and nanosecond == 0) return null;
        if (hour >= 24 or minute > 60 or second >= 60) return error.Overflow;

        return Time.init(hour, minute, second, nanosecond);
    }

    pub const midnight = init(0, 0, 0, 0);
};

pub const DateTime = struct {
    year: i64,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
    nanosecond: u30,
    time_zone: TimeZone,

    pub fn init(date_: Date, time_: Time, time_zone: TimeZone) DateTime {
        return .{
            .year = date_.year,
            .month = date_.month,
            .day = date_.day,
            .hour = time_.hour,
            .minute = time_.minute,
            .second = time_.second,
            .nanosecond = time_.nanosecond,
            .time_zone = time_zone,
        };
    }

    pub fn now() DateTime {
        return fromUnixNanoseconds(std.time.nanoTimestamp());
    }

    pub fn fromUnixSeconds(seconds: i128) DateTime {
        return unix_epoch.add(.seconds, seconds);
    }

    pub fn fromUnixMilliseconds(milliseconds: i128) DateTime {
        return unix_epoch.add(.milliseconds, milliseconds);
    }

    pub fn fromUnixMicroseconds(microseconds: i128) DateTime {
        return unix_epoch.add(.microseconds, microseconds);
    }

    pub fn fromUnixNanoseconds(nanoseconds: i128) DateTime {
        return unix_epoch.add(.nanoseconds, nanoseconds);
    }

    pub fn date(date_time: DateTime) Date {
        return .{
            .year = date_time.year,
            .month = date_time.month,
            .day = date_time.day,
        };
    }

    pub fn time(date_time: DateTime) Time {
        return .{
            .hour = date_time.hour,
            .minute = date_time.minute,
            .second = date_time.second,
            .nanosecond = date_time.nanosecond,
        };
    }

    pub fn unixSeconds(date_time: DateTime) i128 {
        const utc_date_time = date_time.withTimeZone(.utc);
        const days_since_epoch = utc_date_time.dayIndex() - comptime unix_epoch.dayIndex();
        var seconds_since_epoch = days_since_epoch * std.time.s_per_day;
        seconds_since_epoch += @as(i64, utc_date_time.hour) * std.time.s_per_hour;
        seconds_since_epoch += @as(i64, utc_date_time.minute) * std.time.s_per_min;
        seconds_since_epoch += @min(utc_date_time.second, 59);
        return seconds_since_epoch;
    }

    pub fn unixMilliseconds(date_time: DateTime) i128 {
        return @divFloor(date_time.unixNanoseconds(), std.time.ns_per_ms);
    }

    pub fn unixMicroseconds(date_time: DateTime) i128 {
        return @divFloor(date_time.unixNanoseconds(), std.time.ns_per_us);
    }

    pub fn unixNanoseconds(date_time: DateTime) i128 {
        return date_time.unixSeconds() * std.time.ns_per_s + date_time.nanosecond;
    }

    pub fn withTimeZone(date_time: DateTime, new_time_zone: TimeZone) DateTime {
        if (std.meta.eql(date_time.time_zone, new_time_zone)) return date_time;

        var minutes_to_add: i16 = 0;
        const original_offset = date_time.time_zone.asUtcOffset();
        const target_offset = new_time_zone.asUtcOffset();

        switch (target_offset.sign) {
            .positive => {
                minutes_to_add += @as(i16, target_offset.hours) * 60;
                minutes_to_add += target_offset.minutes;
            },
            .negative => {
                minutes_to_add -= @as(i16, target_offset.hours) * 60;
                minutes_to_add -= target_offset.minutes;
            },
        }

        switch (original_offset.sign) {
            .positive => {
                minutes_to_add -= @as(i16, original_offset.hours) * 60;
                minutes_to_add -= original_offset.minutes;
            },
            .negative => {
                minutes_to_add += @as(i16, original_offset.hours) * 60;
                minutes_to_add += original_offset.minutes;
            },
        }

        var result = date_time;
        result.time_zone = new_time_zone;
        result.addToSelf(.minutes, minutes_to_add);
        return result;
    }

    pub fn add(date_time: DateTime, comptime unit: Unit, amount: i128) DateTime {
        if (amount == 0) return date_time;

        var result = date_time;
        result.addToSelf(unit, amount);
        return result;
    }

    pub fn addToSelf(date_time: *DateTime, comptime unit: Unit, amount: i128) void {
        if (amount == 0) return;

        switch (unit) {
            .years => {
                date_time.year = @intCast(i64, std.math.clamp(
                    @as(i128, date_time.year) +| amount,
                    std.math.minInt(i64),
                    std.math.maxInt(i64),
                ));
                date_time.day = @min(date_time.day, date_time.daysInMonth());
            },
            .months => {
                const month_offset = @intCast(i8, @rem(amount, 12));
                const year_offset = @divTrunc(amount, 12);
                var new_month = @as(i8, date_time.month) + month_offset;
                if (new_month < 1) {
                    date_time.year -|= 1;
                    new_month += 12;
                } else if (new_month > 12) {
                    date_time.year +|= 1;
                    new_month -= 12;
                }
                std.debug.assert(new_month >= 1 and new_month <= 12); // Sanity check.
                date_time.month = @intCast(u4, new_month);
                date_time.addToSelf(.years, year_offset);
                date_time.day = @min(date_time.day, date_time.daysInMonth());
            },
            .days => {
                const day_index = date_time.date().dayIndex();
                const new_date = Date.fromDayIndex(day_index + amount);
                date_time.year = new_date.year;
                date_time.month = new_date.month;
                date_time.day = new_date.day;
            },
            .hours => {
                const new_hour = @as(i128, date_time.hour) +| amount;
                date_time.addToSelf(.days, @divFloor(new_hour, 24));
                date_time.hour = @intCast(u5, @mod(new_hour, 24));
            },
            .minutes => {
                const new_minute = @as(i128, date_time.minute) +| amount;
                date_time.addToSelf(.hours, @divFloor(new_minute, 60));
                date_time.minute = @intCast(u6, @mod(new_minute, 60));
            },
            .seconds => {
                const new_second = @as(i128, @min(date_time.second, 59)) +| amount;
                date_time.addToSelf(.minutes, @divFloor(new_second, 60));
                date_time.second = @intCast(u6, @mod(new_second, 60));
            },
            .milliseconds => {
                date_time.addToSelf(.nanoseconds, amount *| std.time.ns_per_ms);
            },
            .microseconds => {
                date_time.addToSelf(.nanoseconds, amount *| std.time.ns_per_us);
            },
            .nanoseconds => {
                const new_nanosecond = @as(i128, date_time.nanosecond) +| amount;
                date_time.addToSelf(.seconds, @divFloor(new_nanosecond, std.time.ns_per_s));
                date_time.nanosecond = @intCast(u30, @mod(new_nanosecond, std.time.ns_per_s));
            },
        }
    }

    /// Whether the current year is a leap year or not.
    pub fn isLeapYear(date_time: DateTime) bool {
        return date_time.date().isLeapYear();
    }

    /// The number of days in the current month.
    pub fn daysInMonth(date_time: DateTime) u5 {
        return date_time.date().daysInMonth();
    }

    /// 0-indexed day of year (January 1st is day 0, February 1st is day 31).
    pub fn dayOfYear(date_time: DateTime) u9 {
        return date_time.date().dayOfYear();
    }

    /// Calculate the number of days since `0000-01-01`.
    pub fn dayIndex(date_time: DateTime) i128 {
        return date_time.date().dayIndex();
    }

    pub fn dayOfWeek(date_time: DateTime) Weekday {
        return date_time.date().dayOfWeek();
    }

    pub fn format(
        date_time: DateTime,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try date_time.date().format(fmt, options, writer);
        try writer.writeByte('T');
        try date_time.time().format(fmt, options, writer);
        try date_time.time_zone.format(fmt, options, writer);
    }

    pub fn parse(buf: []const u8) !DateTime {
        const parser = try DateTimeParser.parse(.date_time, buf);

        const time_ = try Time.parseImpl(parser);
        const date_ = try Date.parseImpl(parser);
        const time_zone = if (parser.time_zone) |time_zone_span|
            try TimeZone.parse(parser.string(time_zone_span))
        else
            .utc;

        var result = init(date_, time_ orelse Time.midnight, time_zone);
        if (time_ == null) result.addToSelf(.days, 1);
        return result;
    }

    /// The Unix epoch: `1970-01-01T00:00:00Z`.
    ///
    /// Unix timestamps are relative to this moment.
    pub const unix_epoch = DateTime.init(Date.unix_epoch, Time.midnight, .utc);
};

pub const TimeZone = union(enum) {
    utc: void,
    utc_offset: UtcOffset,

    pub fn init(sign: UtcOffset.Sign, hours: u5, minutes: u6) TimeZone {
        return .{ .utc_offset = UtcOffset.init(sign, hours, minutes) };
    }

    pub fn asUtcOffset(time_zone: TimeZone) UtcOffset {
        return switch (time_zone) {
            .utc => comptime UtcOffset.init(.positive, 0, 0),
            .utc_offset => |utc_offset| utc_offset,
        };
    }

    pub fn format(
        time_zone: TimeZone,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (time_zone) {
            .utc => try writer.writeByte('Z'),
            .utc_offset => |utc_offset| try utc_offset.format(fmt, options, writer),
        }
    }

    pub fn parse(tz_spec: []const u8) !TimeZone {
        switch (tz_spec.len) {
            1 => switch (tz_spec[0]) {
                'Z' => return .utc,
                else => return error.InvalidCharacter, // Expected "Z" or string in the form "±hh", "±hhmm", or "±hh:mm".
            },
            3, 5, 6 => return .{ .utc_offset = try UtcOffset.parse(tz_spec) },
            else => return error.InvalidLength, // Expected "Z" or string in the form "±hh", "±hhmm", or "±hh:mm".
        }
    }
};

pub const UtcOffset = struct {
    sign: Sign,
    hours: u5,
    minutes: u6,

    pub const Sign = enum {
        positive,
        negative,
    };

    pub fn init(sign: Sign, hours: u5, minutes: u6) UtcOffset {
        std.debug.assert(hours < 24); // Hour offset must be in the range `0...23`.
        std.debug.assert(minutes < 60); // Minute offset must be in the range `0...59`.
        return .{
            .sign = sign,
            .hours = hours,
            .minutes = minutes,
        };
    }

    pub fn asTimeZone(utc_offset: UtcOffset) TimeZone {
        return .{ .utc_offset = utc_offset };
    }

    pub fn format(
        utc_offset: UtcOffset,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeByte(switch (utc_offset.sign) {
            .positive => '+',
            .negative => '-',
        });
        try writer.print("{d:0>2}:{d:0>2}", .{
            utc_offset.hours,
            utc_offset.minutes,
        });
    }

    pub fn parse(tz_spec: []const u8) !UtcOffset {
        const expect_colon_separator = tz_spec.len == 6;
        const hours_only = tz_spec.len == 3;
        switch (tz_spec.len) {
            3, 5, 6 => {},
            else => return error.InvalidLength, // Expected string in the form "±hh", "±hhmm", or "±hh:mm".
        }

        const hour_digit_index: usize = 1;
        const colon_separator_index: usize = 3;
        const minute_digit_index = colon_separator_index + @boolToInt(expect_colon_separator);

        const sign: Sign = switch (tz_spec[0]) {
            '+' => .positive,
            '-' => .negative,
            else => return error.InvalidCharacter, // Expected offset sign ('+' or '-').
        };

        var hours: u5 = 0;
        var hours_out_of_range = false;
        switch (tz_spec[hour_digit_index]) {
            '0'...'2' => |digit| hours += @intCast(u5, digit - '0') * 10,
            '3'...'9' => hours_out_of_range = true,
            else => return error.InvalidCharacter, // Expected the first digit of the hour offset.
        }
        switch (tz_spec[hour_digit_index + 1]) {
            '0'...'9' => |digit| hours += @intCast(u5, digit - '0'),
            else => return error.InvalidCharacter, // Expected the second digit of the hour offset.
        }

        if (expect_colon_separator) {
            switch (tz_spec[colon_separator_index]) {
                ':' => {},
                else => return error.InvalidCharacter, // Expected hour-minute separator (':').
            }
        }

        var minutes: u6 = 0;
        var minutes_out_of_range = false;
        if (!hours_only) {
            switch (tz_spec[minute_digit_index]) {
                '0'...'5' => |digit| minutes += @intCast(u6, digit - '0') * 10,
                '6'...'9' => minutes_out_of_range = true,
                else => return error.InvalidCharacter, // Expected the first digit of the minute offset.
            }
            switch (tz_spec[minute_digit_index + 1]) {
                '0'...'9' => |digit| minutes += @intCast(u6, digit - '0'),
                else => return error.InvalidCharacter, // Expected the second digit of the minute offset.
            }
        }

        if (hours_out_of_range or hours >= 24) return error.Overflow; // Hour offset must be in the range `0...23`.
        if (minutes_out_of_range) return error.Overflow; // Minute offset must be in the range `0...59`.

        return .{
            .sign = sign,
            .hours = hours,
            .minutes = minutes,
        };
    }
};

const DateTimeParser = struct {
    /// The string being parsed.
    buf: []const u8,

    /// The currently parsed index.
    index: u8 = 0,

    /// Whether we are parsing date, time, or the combined representation.
    mode: Mode,

    /// Whether the date/time uses the ISO extended format or not.
    format: ?Format = null,

    /// Whether the date is a calendar date, week date, or ordinal date.
    date_type: ?DateType = null,

    year: ?Span = null,
    month: ?Span = null,
    week: ?Span = null,
    day: ?Span = null,
    hour: ?Span = null,
    minute: ?Span = null,
    second: ?Span = null,
    fraction: ?Span = null,
    time_zone: ?Span = null,

    fn parse(mode: Mode, buf: []const u8) !DateTimeParser {
        var parser: DateTimeParser = .{
            .buf = buf,
            .mode = mode,
        };

        if (parser.buf.len > 64) return error.BufferTooLarge;
        if (parser.mode == .date or parser.mode == .date_time) {
            try parser.parseYear();
            if (parser.date_type != null and parser.date_type.? == .week) {
                try parser.parseWeekDate();
            } else {
                try parser.parseCalendarOrOrdinalDate();
            }
        }

        if (parser.mode == .date) {
            if (parser.index != parser.buf.len) return error.InvalidCharacter;
            return parser;
        }

        switch (parser.peekByte() orelse return error.EndOfBuffer) {
            'T' => parser.index += 1,
            '0'...'9' => if (parser.mode == .date_time) return error.InvalidCharacter,
            else => return error.InvalidCharacter,
        }

        try parser.parseTime();
        if (parser.peekByte() != null) return error.InvalidCharacter;

        return parser;
    }

    fn parseYear(parser: *DateTimeParser) !void {
        const start = parser.index;
        const sign = parser.peekByte() orelse return error.EndOfBuffer;
        const has_sign = sign == '+' or sign == '-';
        if (has_sign) {
            try parser.setFormat(.extended);
            parser.index += 1;
        }
        var num_digits: u8 = 0;
        while (true) {
            const byte = try parser.readByte();
            switch (byte) {
                '0'...'9' => {
                    if (num_digits < 4 or has_sign) {
                        num_digits += 1;
                    } else {
                        try parser.setFormat(.basic);
                        parser.index -= 1;
                        break;
                    }
                },
                '-' => {
                    if (num_digits < 4) return error.InvalidCharacter;
                    try parser.setFormat(.extended);
                    if (parser.peekByte()) |next_byte| {
                        if (next_byte == 'W') {
                            try parser.setDateType(.week);
                            parser.index += 1;
                        }
                    }
                    break;
                },
                'W' => {
                    if (num_digits < 4) return error.InvalidCharacter;
                    try parser.setFormat(.basic);
                    try parser.setDateType(.week);
                    break;
                },
                else => return error.InvalidCharacter,
            }
        }
        parser.year = .{ start, start + @boolToInt(has_sign) + num_digits };
    }

    fn parseWeekDate(parser: *DateTimeParser) !void {
        const week: Span = .{ parser.index, parser.index + 2 };
        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }
        switch (parser.peekByte() orelse return error.EndOfBuffer) {
            '0'...'9' => {
                try parser.setFormat(.basic);
            },
            '-' => {
                try parser.setFormat(.extended);
                parser.index += 1;
            },
            else => return error.InvalidCharacter,
        }

        const day: Span = .{ parser.index, parser.index + 1 };
        switch (parser.readByte() catch unreachable) {
            '0'...'9' => {},
            else => return error.InvalidCharacter,
        }

        if (parser.peekByte()) |next_byte| {
            switch (next_byte) {
                'T' => if (parser.mode != .date_time) return error.InvalidCharacter,
                else => return error.InvalidCharacter,
            }
        } else if (parser.mode == .date_time) return error.EndOfBuffer;

        parser.week = week;
        parser.day = day;
    }

    fn parseCalendarOrOrdinalDate(parser: *DateTimeParser) !void {
        const start = parser.index;

        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }

        switch (try parser.readByte()) {
            '0'...'9' => {
                if (parser.peekByte()) |next_byte| {
                    switch (next_byte) {
                        '0'...'9' => {
                            try parser.setFormat(.basic);
                            try parser.setDateType(.calendar);
                            parser.index += 1;
                            parser.month = .{ start, start + 2 };
                            parser.day = .{ start + 2, start + 4 };
                            return;
                        },
                        'T' => {
                            if (parser.mode != .date_time) return error.InvalidCharacter;
                            try parser.setDateType(.ordinal);
                            parser.day = .{ start, start + 3 };
                            return;
                        },
                        else => return error.InvalidCharacter,

                    }
                } else {
                    if (parser.mode == .date_time) return error.EndOfBuffer;
                    try parser.setDateType(.ordinal);
                    parser.day = .{ start, start + 3 };
                    return;
                }
            },
            '-' => {
                try parser.setFormat(.extended);
                try parser.setDateType(.calendar);
            },
            else => return error.InvalidCharacter,
        }

        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }

        parser.month = .{ start, start + 2 };
        parser.day = .{ start + 3, start + 5 };
    }

    fn parseTime(parser: *DateTimeParser) !void {
        if (try parser.parseHour()) {
            if (try parser.parseMinute()) {
                if (try parser.parseSecond()) {
                    try parser.parseFraction();
                }
            }
        }
        if (parser.index < parser.buf.len) {
            parser.time_zone = .{ parser.index, @intCast(u8, parser.buf.len) };
            parser.index = parser.time_zone.?[1];
        }
    }

    fn parseHour(parser: *DateTimeParser) !bool {
        parser.hour = .{ parser.index, parser.index + 2 };

        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }

        if (parser.peekByte()) |next_byte| {
            switch (next_byte) {
                'Z', '+', '-' => return false,
                '0'...'9' => {
                    try parser.setFormat(.basic);
                },
                ':' => {
                    try parser.setFormat(.extended);
                    parser.index += 1;
                },
                else => return error.InvalidCharacter,
            }
        } else return false;

        return true;
    }

    fn parseMinute(parser: *DateTimeParser) !bool {
        parser.minute = .{ parser.index, parser.index + 2 };

        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }

        if (parser.peekByte()) |next_byte| {
            switch (next_byte) {
                'Z', '+', '-' => return false,
                '0'...'9' => {
                    try parser.setFormat(.basic);
                },
                ':' => {
                    try parser.setFormat(.extended);
                    parser.index += 1;
                },
                else => return error.InvalidCharacter,
            }
        } else return false;

        return true;
    }

    fn parseSecond(parser: *DateTimeParser) !bool {
        parser.second = .{ parser.index, parser.index + 2 };

        for (0..2) |_| {
            switch (try parser.readByte()) {
                '0'...'9' => {},
                else => return error.InvalidCharacter,
            }
        }

        if (parser.peekByte()) |next_byte| {
            switch (next_byte) {
                'Z', '+', '-' => return false,
                '.', ',' => parser.index += 1,
                else => return error.InvalidCharacter,
            }
        } else return false;

        return true;
    }

    fn parseFraction(parser: *DateTimeParser) !void {
        const start = parser.index;

        var num_digits: u8 = 0;
        while (parser.peekByte()) |byte| {
            switch (byte) {
                '0'...'9' => {
                    parser.index += 1;
                    num_digits += 1;
                },
                'Z', '+', '-' => break,
                else => return error.InvalidCharacter,
            }
        }
        if (num_digits < 1) return error.InvalidCharacter;

        parser.fraction = .{ start, start + num_digits };
    }

    fn peekByte(parser: *DateTimeParser) ?u8 {
        if (parser.buf.len <= parser.index) return null;
        return parser.buf[parser.index];
    }

    fn readByte(parser: *DateTimeParser) !u8 {
        if (parser.buf.len <= parser.index) return error.EndOfBuffer;
        defer parser.index += 1;
        return parser.buf[parser.index];
    }

    fn setFormat(parser: *DateTimeParser, format: Format) !void {
        if (parser.format) |current_format| {
            if (current_format != format) return error.ConflictingFormat;
        }
        parser.format = format;
    }

    fn setDateType(parser: *DateTimeParser, date_type: DateType) !void {
        if (parser.date_type) |current_date_type| {
            if (current_date_type != date_type) return error.ConflictingDateType;
        }
        parser.date_type = date_type;
    }

    fn string(parser: DateTimeParser, span: Span) []const u8 {
        return parser.buf[span[0]..span[1]];
    }

    const Format = enum {
        basic,
        extended,
    };

    const DateType = enum {
        calendar,
        ordinal,
        week,
    };

    const Mode = enum {
        date,
        time,
        date_time,
    };

    const Span = struct { u8, u8 };
};

/// The number of days in 400 years.
const days_in_400_years = 400 * 365 + 100 - 3;

/// The number of days in 4 years, none of which are divisible by 100.
const days_in_4_years = 4 * 365 + 1;

/// The number of days from `0000-01-01` to `0101-01-01`.
const year_101_january_1st = 101 * 365 + 25;

/// The number of days from `0000-01-01` to `0201-01-01`.
const year_201_january_1st = 201 * 365 + 49;

/// The number of days from `0000-01-01` to `0301-01-01`.
const year_301_january_1st = 301 * 365 + 73;

test "UtcOffset initialization" {
    try expectEqual(
        UtcOffset{
            .sign = .positive,
            .hours = 0,
            .minutes = 0,
        },
        UtcOffset.init(.positive, 0, 0),
    );

    try expectEqual(
        UtcOffset{
            .sign = .positive,
            .hours = 0,
            .minutes = 26,
        },
        UtcOffset.init(.positive, 0, 26),
    );

    try expectEqual(
        UtcOffset{
            .sign = .negative,
            .hours = 0,
            .minutes = 26,
        },
        UtcOffset.init(.negative, 0, 26),
    );

    try expectEqual(
        UtcOffset{
            .sign = .positive,
            .hours = 12,
            .minutes = 0,
        },
        UtcOffset.init(.positive, 12, 0),
    );

    try expectEqual(
        UtcOffset{
            .sign = .negative,
            .hours = 12,
            .minutes = 0,
        },
        UtcOffset.init(.negative, 12, 0),
    );

    try expectEqual(
        UtcOffset{
            .sign = .positive,
            .hours = 12,
            .minutes = 38,
        },
        UtcOffset.init(.positive, 12, 38),
    );

    try expectEqual(
        UtcOffset{
            .sign = .negative,
            .hours = 12,
            .minutes = 38,
        },
        UtcOffset.init(.negative, 12, 38),
    );

    try expectEqual(
        UtcOffset{
            .sign = .positive,
            .hours = 23,
            .minutes = 59,
        },
        UtcOffset.init(.positive, 23, 59),
    );

    try expectEqual(
        UtcOffset{
            .sign = .negative,
            .hours = 23,
            .minutes = 59,
        },
        UtcOffset.init(.negative, 23, 59),
    );
}

test "UtcOffset parsing" {
    try expectEqual(UtcOffset.init(.positive, 0, 0), try UtcOffset.parse("+00"));
    try expectEqual(UtcOffset.init(.positive, 0, 0), try UtcOffset.parse("+0000"));
    try expectEqual(UtcOffset.init(.positive, 0, 0), try UtcOffset.parse("+00:00"));

    try expectEqual(UtcOffset.init(.positive, 0, 26), try UtcOffset.parse("+0026"));
    try expectEqual(UtcOffset.init(.positive, 0, 26), try UtcOffset.parse("+00:26"));
    try expectEqual(UtcOffset.init(.negative, 0, 26), try UtcOffset.parse("-0026"));
    try expectEqual(UtcOffset.init(.negative, 0, 26), try UtcOffset.parse("-00:26"));

    try expectEqual(UtcOffset.init(.positive, 12, 0), try UtcOffset.parse("+12"));
    try expectEqual(UtcOffset.init(.positive, 12, 0), try UtcOffset.parse("+1200"));
    try expectEqual(UtcOffset.init(.positive, 12, 0), try UtcOffset.parse("+12:00"));
    try expectEqual(UtcOffset.init(.negative, 12, 0), try UtcOffset.parse("-12"));
    try expectEqual(UtcOffset.init(.negative, 12, 0), try UtcOffset.parse("-1200"));
    try expectEqual(UtcOffset.init(.negative, 12, 0), try UtcOffset.parse("-12:00"));

    try expectEqual(UtcOffset.init(.positive, 12, 38), try UtcOffset.parse("+1238"));
    try expectEqual(UtcOffset.init(.positive, 12, 38), try UtcOffset.parse("+12:38"));
    try expectEqual(UtcOffset.init(.negative, 12, 38), try UtcOffset.parse("-1238"));
    try expectEqual(UtcOffset.init(.negative, 12, 38), try UtcOffset.parse("-12:38"));

    try expectEqual(UtcOffset.init(.positive, 23, 59), try UtcOffset.parse("+2359"));
    try expectEqual(UtcOffset.init(.positive, 23, 59), try UtcOffset.parse("+23:59"));
    try expectEqual(UtcOffset.init(.negative, 23, 59), try UtcOffset.parse("-2359"));
    try expectEqual(UtcOffset.init(.negative, 23, 59), try UtcOffset.parse("-23:59"));
}

test "UtcOffset parse errors" {
    try expectError(error.InvalidLength, UtcOffset.parse("Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("A"));
    try expectError(error.InvalidLength, UtcOffset.parse("+"));
    try expectError(error.InvalidLength, UtcOffset.parse("-"));

    try expectError(error.InvalidLength, UtcOffset.parse("+0"));
    try expectError(error.InvalidLength, UtcOffset.parse("-0"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z0"));
    try expectError(error.InvalidLength, UtcOffset.parse("A0"));
    try expectError(error.InvalidLength, UtcOffset.parse("00"));
    try expectError(error.InvalidLength, UtcOffset.parse("12"));
    try expectError(error.InvalidLength, UtcOffset.parse("24"));
    try expectError(error.InvalidLength, UtcOffset.parse("48"));

    try expectError(error.InvalidCharacter, UtcOffset.parse("Z00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("Z12"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("Z24"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("Z48"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+Z0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-Z0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+0Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-0Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+1Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-1Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+2Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-2Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+4Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-4Z"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("_12"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("_24"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("_48"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+1_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-1_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+2_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-2_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+4_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-4_"));
    try expectError(error.Overflow, UtcOffset.parse("+24"));
    try expectError(error.Overflow, UtcOffset.parse("-24"));
    try expectError(error.Overflow, UtcOffset.parse("+48"));
    try expectError(error.Overflow, UtcOffset.parse("-48"));

    try expectError(error.InvalidLength, UtcOffset.parse("Z+00"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z-00"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z+12"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z-12"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z+24"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z-24"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z+48"));
    try expectError(error.InvalidLength, UtcOffset.parse("Z-48"));
    try expectError(error.InvalidLength, UtcOffset.parse("A+00"));
    try expectError(error.InvalidLength, UtcOffset.parse("A-00"));
    try expectError(error.InvalidLength, UtcOffset.parse("A+12"));
    try expectError(error.InvalidLength, UtcOffset.parse("A-12"));
    try expectError(error.InvalidLength, UtcOffset.parse("A+24"));
    try expectError(error.InvalidLength, UtcOffset.parse("A-24"));
    try expectError(error.InvalidLength, UtcOffset.parse("A+48"));
    try expectError(error.InvalidLength, UtcOffset.parse("A-48"));
    try expectError(error.InvalidLength, UtcOffset.parse("+000"));
    try expectError(error.InvalidLength, UtcOffset.parse("-000"));
    try expectError(error.InvalidLength, UtcOffset.parse("+00Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("-00Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("+00A"));
    try expectError(error.InvalidLength, UtcOffset.parse("-00A"));
    try expectError(error.InvalidLength, UtcOffset.parse("+00:"));
    try expectError(error.InvalidLength, UtcOffset.parse("-00:"));
    try expectError(error.InvalidLength, UtcOffset.parse("+120"));
    try expectError(error.InvalidLength, UtcOffset.parse("-120"));
    try expectError(error.InvalidLength, UtcOffset.parse("+012"));
    try expectError(error.InvalidLength, UtcOffset.parse("-012"));
    try expectError(error.InvalidLength, UtcOffset.parse("+12Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("-12Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("+12A"));
    try expectError(error.InvalidLength, UtcOffset.parse("-12A"));
    try expectError(error.InvalidLength, UtcOffset.parse("+12:"));
    try expectError(error.InvalidLength, UtcOffset.parse("-12:"));
    try expectError(error.InvalidLength, UtcOffset.parse("+240"));
    try expectError(error.InvalidLength, UtcOffset.parse("-240"));
    try expectError(error.InvalidLength, UtcOffset.parse("+024"));
    try expectError(error.InvalidLength, UtcOffset.parse("-024"));
    try expectError(error.InvalidLength, UtcOffset.parse("+24Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("-24Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("+24A"));
    try expectError(error.InvalidLength, UtcOffset.parse("-24A"));
    try expectError(error.InvalidLength, UtcOffset.parse("+24:"));
    try expectError(error.InvalidLength, UtcOffset.parse("-24:"));
    try expectError(error.InvalidLength, UtcOffset.parse("+480"));
    try expectError(error.InvalidLength, UtcOffset.parse("-480"));
    try expectError(error.InvalidLength, UtcOffset.parse("+048"));
    try expectError(error.InvalidLength, UtcOffset.parse("-048"));
    try expectError(error.InvalidLength, UtcOffset.parse("+48Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("-48Z"));
    try expectError(error.InvalidLength, UtcOffset.parse("+48A"));
    try expectError(error.InvalidLength, UtcOffset.parse("-48A"));
    try expectError(error.InvalidLength, UtcOffset.parse("+48:"));
    try expectError(error.InvalidLength, UtcOffset.parse("-48:"));

    try expectError(error.InvalidCharacter, UtcOffset.parse("Z00:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("Z0000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("A00:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("A0000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+Z000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-Z000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+0_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-0_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+00_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-00_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+000_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-000_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+_800"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-_800"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+4_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-4_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+48_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-48_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+489_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-489_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+00:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-00:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+00:9"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-00:9"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+12:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-12:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+48:0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-48:0"));
    try expectError(error.Overflow, UtcOffset.parse("+2400"));
    try expectError(error.Overflow, UtcOffset.parse("-2400"));
    try expectError(error.Overflow, UtcOffset.parse("+4800"));
    try expectError(error.Overflow, UtcOffset.parse("-4800"));
    try expectError(error.Overflow, UtcOffset.parse("+1260"));
    try expectError(error.Overflow, UtcOffset.parse("-1260"));
    try expectError(error.Overflow, UtcOffset.parse("+1299"));
    try expectError(error.Overflow, UtcOffset.parse("-1299"));

    try expectError(error.InvalidCharacter, UtcOffset.parse("Z00000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("A00000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("000000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24000"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+_0:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-_0:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+2_:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-2_:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+00_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-00_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24_00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24:_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24:_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24:0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24:0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+24:9_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-24:9_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+4_:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-4_:00"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+48:_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-48:_0"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+48:0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-48:0_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("+48:9_"));
    try expectError(error.InvalidCharacter, UtcOffset.parse("-48:9_"));
    try expectError(error.Overflow, UtcOffset.parse("+24:00"));
    try expectError(error.Overflow, UtcOffset.parse("-24:00"));
    try expectError(error.Overflow, UtcOffset.parse("+48:00"));
    try expectError(error.Overflow, UtcOffset.parse("-48:00"));
    try expectError(error.Overflow, UtcOffset.parse("+12:60"));
    try expectError(error.Overflow, UtcOffset.parse("-12:60"));
    try expectError(error.Overflow, UtcOffset.parse("+12:99"));
    try expectError(error.Overflow, UtcOffset.parse("-12:99"));

    try expectError(error.InvalidLength, UtcOffset.parse("Z000000"));
    try expectError(error.InvalidLength, UtcOffset.parse("A000000"));
    try expectError(error.InvalidLength, UtcOffset.parse("0000000"));
    try expectError(error.InvalidLength, UtcOffset.parse("+000000"));
    try expectError(error.InvalidLength, UtcOffset.parse("-000000"));
    try expectError(error.InvalidLength, UtcOffset.parse("+00:000"));
    try expectError(error.InvalidLength, UtcOffset.parse("-00:000"));
    try expectError(error.InvalidLength, UtcOffset.parse("+000:00"));
    try expectError(error.InvalidLength, UtcOffset.parse("-000:00"));
}

test "Date day index" {
    try expectEqual(try Date.init(0, 1, 1), Date.fromDayIndex(0));
    try expectEqual(try Date.init(1, 1, 1), Date.fromDayIndex(366));
    try expectEqual(try Date.init(1970, 1, 1), Date.fromDayIndex(719_528));
    try expectEqual(try Date.init(2023, 5, 14), Date.fromDayIndex(739_019));
    try expectEqual(try Date.init(-1, 1, 1), Date.fromDayIndex(-365));

    try expectEqual(@as(i128, 0), (try Date.init(0, 1, 1)).dayIndex());
    try expectEqual(@as(i128, 366), (try Date.init(1, 1, 1)).dayIndex());
    try expectEqual(@as(i128, 719_528), (try Date.init(1970, 1, 1)).dayIndex());
    try expectEqual(@as(i128, 739_019), (try Date.init(2023, 5, 14)).dayIndex());
    try expectEqual(@as(i128, -365), (try Date.init(-1, 1, 1)).dayIndex());
}

test "Date add" {
    const date = try Date.init(1970, 1, 1);
    const next_year = try Date.init(1971, 1, 1);
    const next_day = try Date.init(1970, 1, 2);

    try expectEqual(next_year, date.add(.years, 1));
    try expectEqual(next_year, date.add(.days, 365));
    try expectEqual(next_year, date.add(.hours, 365 * 24));
    try expectEqual(next_year, date.add(.minutes, 365 * 24 * 60));
    try expectEqual(next_year, date.add(.seconds, 365 * 24 * 60 * 60));
    try expectEqual(next_year, date.add(.nanoseconds, 365 * 24 * 60 * 60 * std.time.ns_per_s));

    try expectEqual(next_day, date.add(.days, 1));
    try expectEqual(next_day, date.add(.hours, 24));
    try expectEqual(next_day, date.add(.hours, 36));
    try expectEqual(next_day, date.add(.minutes, 24 * 60));
    try expectEqual(next_day, date.add(.minutes, 36 * 60));
    try expectEqual(next_day, date.add(.seconds, 24 * 60 * 60));
    try expectEqual(next_day, date.add(.seconds, 36 * 60 * 60));
    try expectEqual(next_day, date.add(.nanoseconds, 24 * 60 * 60 * std.time.ns_per_s));
    try expectEqual(next_day, date.add(.nanoseconds, 36 * 60 * 60 * std.time.ns_per_s));
}

test "Weekday add" {
    try expectEqual(Weekday.monday, Weekday.sunday.add(1));
    try expectEqual(Weekday.monday, Weekday.saturday.add(2));
    try expectEqual(Weekday.saturday, Weekday.monday.add(5));
    try expectEqual(Weekday.sunday, Weekday.monday.add(6));
    try expectEqual(Weekday.monday, Weekday.monday.add(7));
    try expectEqual(Weekday.monday, Weekday.monday.add(14));
    try expectEqual(Weekday.monday, Weekday.monday.add(14 * std.math.maxInt(u64)));

    try expectEqual(Weekday.sunday, Weekday.monday.add(-1));
    try expectEqual(Weekday.saturday, Weekday.monday.add(-2));
    try expectEqual(Weekday.monday, Weekday.saturday.add(-5));
    try expectEqual(Weekday.monday, Weekday.sunday.add(-6));
    try expectEqual(Weekday.monday, Weekday.monday.add(-7));
    try expectEqual(Weekday.monday, Weekday.monday.add(-14));
    try expectEqual(Weekday.monday, Weekday.monday.add(-14 * std.math.maxInt(u64)));
}

test "Day of week" {
    try expectEqual(Weekday.monday, (try Date.init(1, 1, 1)).dayOfWeek());
    try expectEqual(Weekday.saturday, (try Date.init(0, 1, 1)).dayOfWeek());
    try expectEqual(Weekday.sunday, Date.fromDayIndex(1).dayOfWeek());
    try expectEqual(Weekday.tuesday, Date.fromDayIndex(367).dayOfWeek());
    try expectEqual(Weekday.friday, Date.fromDayIndex(-1).dayOfWeek());
    try expectEqual(Weekday.wednesday, (try Date.init(-1, 12, 29)).dayOfWeek());
    try expectEqual(Weekday.sunday, (try Date.init(2023, 5, 14)).dayOfWeek());
    try expectEqual(Weekday.monday, Date.fromDayIndex(739_020).dayOfWeek());
}

test "Unix timestamps" {
    try expectEqual(
        DateTime{
            .year = 1970,
            .month = 1,
            .day = 1,
            .hour = 0,
            .minute = 0,
            .second = 0,
            .nanosecond = 0,
            .time_zone = .utc,
        },
        DateTime.unix_epoch,
    );

    try expectEqual(@as(i128, 0), DateTime.unix_epoch.unixSeconds());
    try expectEqual(@as(i128, 0), DateTime.unix_epoch.unixMilliseconds());
    try expectEqual(@as(i128, 0), DateTime.unix_epoch.unixNanoseconds());
    try expectEqual(DateTime.unix_epoch, DateTime.fromUnixSeconds(0));
    try expectEqual(DateTime.unix_epoch, DateTime.fromUnixMilliseconds(0));
    try expectEqual(DateTime.unix_epoch, DateTime.fromUnixNanoseconds(0));

    const date_time_1 = DateTime.init(try Date.init(2023, 5, 15), Time.init(16, 24, 11, 0), .utc);
    const date_time_2 = date_time_1.add(.milliseconds, 123);
    const date_time_3 = date_time_2.add(.microseconds, 456);
    const date_time_4 = date_time_3.add(.nanoseconds, 789);

    try expectEqual(@as(u6, 11), date_time_1.second);
    try expectEqual(@as(u6, 11), date_time_2.second);
    try expectEqual(@as(u6, 11), date_time_3.second);
    try expectEqual(@as(u6, 11), date_time_4.second);

    try expectEqual(@as(u30, 0), date_time_1.nanosecond);
    try expectEqual(@as(u30, 123 * std.time.ns_per_ms), date_time_2.nanosecond);
    try expectEqual(@as(u30, 123456 * std.time.ns_per_us), date_time_3.nanosecond);
    try expectEqual(@as(u30, 123456789), date_time_4.nanosecond);

    try expectEqual(@as(i128, 1684167851), date_time_1.unixSeconds());
    try expectEqual(@as(i128, 1684167851000), date_time_1.unixMilliseconds());
    try expectEqual(@as(i128, 1684167851000000), date_time_1.unixMicroseconds());
    try expectEqual(@as(i128, 1684167851000000000), date_time_1.unixNanoseconds());
    try expectEqual(date_time_1, DateTime.fromUnixSeconds(1684167851));
    try expectEqual(date_time_1, DateTime.fromUnixMilliseconds(1684167851000));
    try expectEqual(date_time_1, DateTime.fromUnixMicroseconds(1684167851000000));
    try expectEqual(date_time_1, DateTime.fromUnixNanoseconds(1684167851000000000));
    
    try expectEqual(@as(i128, 1684167851), date_time_2.unixSeconds());
    try expectEqual(@as(i128, 1684167851123), date_time_2.unixMilliseconds());
    try expectEqual(@as(i128, 1684167851123000), date_time_2.unixMicroseconds());
    try expectEqual(@as(i128, 1684167851123000000), date_time_2.unixNanoseconds());
    try expectEqual(date_time_2, DateTime.fromUnixMilliseconds(1684167851123));
    try expectEqual(date_time_2, DateTime.fromUnixMicroseconds(1684167851123000));
    try expectEqual(date_time_2, DateTime.fromUnixNanoseconds(1684167851123000000));

    try expectEqual(@as(i128, 1684167851), date_time_3.unixSeconds());
    try expectEqual(@as(i128, 1684167851123), date_time_3.unixMilliseconds());
    try expectEqual(@as(i128, 1684167851123456), date_time_3.unixMicroseconds());
    try expectEqual(@as(i128, 1684167851123456000), date_time_3.unixNanoseconds());
    try expectEqual(date_time_3, DateTime.fromUnixMicroseconds(1684167851123456));
    try expectEqual(date_time_3, DateTime.fromUnixNanoseconds(1684167851123456000));

    try expectEqual(@as(i128, 1684167851), date_time_4.unixSeconds());
    try expectEqual(@as(i128, 1684167851123), date_time_4.unixMilliseconds());
    try expectEqual(@as(i128, 1684167851123456), date_time_4.unixMicroseconds());
    try expectEqual(@as(i128, 1684167851123456789), date_time_4.unixNanoseconds());
    try expectEqual(date_time_4, DateTime.fromUnixNanoseconds(1684167851123456789));
}

test "Date/time parsing" {
    const date_time_1 = DateTime.init(
        try Date.init(2023, 5, 15),
        Time.init(21, 20, 43, 123 * std.time.ns_per_ms),
        TimeZone.init(.negative, 4, 0),
    );

    try expectEqual(date_time_1, try DateTime.parse("2023-05-15T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("2023-05-15T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("2023-W20-1T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("2023-W20-1T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("2023-135T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("2023-135T21:20:43,123-04:00"));

    try expectEqual(date_time_1, try DateTime.parse("20230515T212043.123-0400"));
    try expectEqual(date_time_1, try DateTime.parse("20230515T212043,123-0400"));
    try expectEqual(date_time_1, try DateTime.parse("2023W201T212043.123-0400"));
    try expectEqual(date_time_1, try DateTime.parse("2023W201T212043,123-0400"));
    try expectEqual(date_time_1, try DateTime.parse("2023135T212043.123-0400"));
    try expectEqual(date_time_1, try DateTime.parse("2023135T212043,123-0400"));

    try expectEqual(date_time_1, try DateTime.parse("+2023-05-15T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+2023-05-15T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+2023-W20-1T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+2023-W20-1T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+2023-135T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+2023-135T21:20:43,123-04:00"));

    try expectEqual(date_time_1, try DateTime.parse("+02023-05-15T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+02023-05-15T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+02023-W20-1T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+02023-W20-1T21:20:43,123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+02023-135T21:20:43.123-04:00"));
    try expectEqual(date_time_1, try DateTime.parse("+02023-135T21:20:43,123-04:00"));

    const date_time_2 = DateTime.init(
        try Date.init(99_999, 6, 21),
        Time.init(15, 42, 6, 0),
        .utc,
    );

    try expectEqual(date_time_2, try DateTime.parse("+99999-06-21T15:42:06Z"));
    try expectEqual(date_time_2, try DateTime.parse("+099999-06-21T15:42:06Z"));

    const date_time_3 = DateTime.init(
        try Date.init(-99_999, 6, 21),
        Time.init(15, 42, 6, 0),
        .utc,
    );
    try expectEqual(date_time_3, try DateTime.parse("-99999-06-21T15:42:06Z"));
    try expectEqual(date_time_3, try DateTime.parse("-099999-06-21T15:42:06Z"));

    try expectError(error.ConflictingFormat, DateTime.parse("20230515T21:20:43Z"));
    try expectError(error.ConflictingFormat, DateTime.parse("2023-05-15T212043Z"));
    try expectError(error.ConflictingFormat, Date.parse("+2023W201"));
    try expectError(error.InvalidCharacter, DateTime.parse("+999990515T"));
    try expectError(error.InvalidCharacter, Date.parse("202-05-15"));
}

test "Week dates" {
    const date_1 = try Date.init(2008, 12, 28);
    try expectEqual(
        WeekDate{
            .year = 2008,
            .week = 52,
            .day = .sunday,
        },
        date_1.weekDate(),
    );
    try expectFmt("2008-W52-7", "{}", .{ date_1.weekDate() });

    const date_2 = try Date.init(2008, 12, 29);
    try expectEqual(
        WeekDate{
            .year = 2009,
            .week = 1,
            .day = .monday,
        },
        date_2.weekDate(),
    );
    try expectFmt("2009-W01-1", "{}", .{ date_2.weekDate() });

    const date_3 = try Date.init(2010, 1, 3);
    try expectEqual(
        WeekDate{
            .year = 2009,
            .week = 53,
            .day = .sunday,
        },
        date_3.weekDate(),
    );
    try expectFmt("2009-W53-7", "{}", .{ date_3.weekDate() });

    const date_4 = try Date.init(2010, 1, 4);
    try expectEqual(
        WeekDate{
            .year = 2010,
            .week = 1,
            .day = .monday,
        },
        date_4.weekDate(),
    );
    try expectFmt("2010-W01-1", "{}", .{ date_4.weekDate() });
}
