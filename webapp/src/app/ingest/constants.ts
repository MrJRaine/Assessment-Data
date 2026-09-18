/**
 * Shared between the ingest server actions and the panel that renders them.
 *
 * Lives here rather than in actions.ts because a `'use server'` module may only export async
 * functions — a plain const is a build error there.
 */

/**
 * Minutes of warning teachers get before an ingest runs.
 *
 * Long enough that the staged banner -> lock -> auto-save sequence completes on every open tab,
 * INCLUDING backgrounded ones: hidden tabs only poll every 8 minutes, so a notice much shorter than
 * this can elapse before a hidden tab ever learns about it and flushes the teacher's work.
 */
export const INGEST_NOTICE_MINUTES = 15
