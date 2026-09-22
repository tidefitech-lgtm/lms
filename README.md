# TIDEF ITECH LMS — Phase 1 (Supabase)

Vanilla HTML/CSS/JS + Supabase (Postgres + Auth + Storage). No React, no
build step, no online payment. This phase covers: project structure,
Supabase connection, registration, login, logout, email verification,
password reset, auth guards, roles, and the Student ID column (assigned
by an admin action in Phase 2).

## 1. Create your Supabase project

1. Go to https://supabase.com/dashboard → **New project**.
2. Pick an org, name it (e.g. `tidef-itech-lms`), set a strong database
   password (save it somewhere), pick a region close to Nigeria (Europe
   regions are usually lowest-latency — Supabase doesn't yet have a West
   Africa region), and create the project. It takes a minute or two to
   provision.

## 2. Get your API keys

1. In the project: **Project Settings → API**.
2. Copy the **Project URL** and the **anon / public** key.
3. Paste both into `js/supabase.js`, replacing the placeholder values.

Never use the **service_role** key here — that key bypasses Row Level
Security entirely and must never be shipped to a browser.

## 3. Run the database migration

1. In the project: **SQL Editor → New query**.
2. Open `supabase/migrations/0001_init.sql` from this project, copy the
   whole file, paste it into the SQL editor, and click **Run**.

This creates the `profiles`, `courses`, `payment_confirmations`,
`payment_approval_logs`, and `notifications` tables, the trigger that
auto-creates a profile row on signup, the trigger that blocks
self-privilege-escalation, all the Row Level Security policies, and the
`profile-photos` storage bucket with its access policies.

(If you prefer the CLI/migrations workflow instead of pasting into the
dashboard: `npm install -g supabase`, `supabase login`, `supabase link
--project-ref your-project-ref`, then `supabase db push` from this
folder — it picks up everything under `supabase/migrations/` automatically.)

## 4. Configure OTP verification

1. **Authentication → Providers → Email** — make sure **Confirm email**
   is switched **on**. First click **Set up SMTP** on the Email Templates
   page and configure a real SMTP provider such as Resend, Brevo, SendGrid,
   or Gmail SMTP. Supabase's default email service does not allow custom
   templates.
2. After SMTP is configured, open **Authentication → Email Templates → Confirm
   signup** and replace the template with one that includes `{{ .Token }}`.
   Remove every `{{ .ConfirmationURL }}` link from this template. For example:

```html
<h2>Confirm your TIDEF ITECH account</h2>
<p>Your verification code is:</p>
<p style="font-size:32px;font-weight:700;letter-spacing:6px;">{{ .Token }}</p>
<p>
  This code expires soon. If you did not create an account, ignore this email.
</p>
```

The registration page verifies this code with `verifyOtp`. 3. **Authentication → URL Configuration** — set:

- **Site URL**: wherever you'll host this (e.g. `https://lms.tidefitech.com`,
  or `http://localhost:3000` while testing locally)
- **Redirect URLs**: add both `/verify-email.html` and
  `/reset-password.html` under that same origin, since those are the
  pages Supabase redirects to after password-reset email links. Signup
  verification stays on `verify-email.html` and uses an OTP.

Password-reset email templates can continue using Supabase's default link.

## 5. Run it locally

Because pages use ES module `<script type="module">` and talk to
Supabase, you need a local web server (not `file://`):

```bash
npx serve .
# or: python3 -m http.server 5000
```

Open the printed local URL and go to `/register.html`. Make sure the URL
you're testing on matches whatever you set as the Site URL in step 4, or
the email confirmation redirect won't land correctly.

## 6. Create your first Admin account

There's no public "become an admin" button (by design). To create your
first Admin/Super Admin:

1. Register a normal account through `/register.html` with the email you
   want as admin, and confirm it via the email link.
2. Open **Supabase Dashboard → Table Editor → `profiles` → your row**.
3. Edit two fields:
   - `role` → `super_admin`
   - `account_status` → `approved`
4. Log out and back in — you'll land on `/admin/dashboard.html`.

From there, that Super Admin can promote other users to `teacher` or
`admin` once the Admin → Users page ships (Phase 9); for now this is
also done via the Table Editor.

## 7. What's in this phase

```
login.html                     Email/phone + password login
register.html                  Student self-registration (role fixed to "student")
verify-email.html              Verifies signup OTPs sent by email
reset-password.html            Handles the Supabase password-reset redirect
forgot-password.html           Requests a password reset email
student/pending-approval.html  Shown to students whose account isn't approved yet
student/dashboard.html         Guarded dashboard shell for approved students
teacher/dashboard.html         Guarded dashboard shell for teachers
admin/dashboard.html           Guarded dashboard shell with live student counts

js/supabase.js     Supabase client init — put your project URL + anon key here
js/config.js        Roles, statuses, and other shared constants
js/auth.js          register / login / logout / verify / reset / new password
js/guards.js        requireAuth() — protects pages by role + approval status
js/components.js    Shared sidebar/topbar shell, built per role
js/utils.js         Toasts, form errors, formatting helpers

supabase/migrations/0001_init.sql   The entire schema + RLS + storage setup
                                     (the real access-control boundary)
```

## 8. Security model (why it's safe)

- A new profile row is created **only** by a database trigger on
  `auth.users` insert. That trigger reads just the safe, self-descriptive
  fields out of signup metadata (`full_name`, `phone`, `dob`, `gender`,
  `address`, `interested_course_id`) — it never reads `role`,
  `account_status`, `payment_status`, or `student_id` from anything the
  client sent, so those columns always start at their table defaults.
  There is no INSERT policy on `profiles` at all, so a client can't
  create a row directly even if it tried.
- After creation, a second trigger (`protect_privileged_fields`) fires on
  every UPDATE and blocks any change to `role`, `account_status`,
  `payment_status`, `enrollment_status`, or `student_id` unless the actor
  is `admin`/`super_admin` — and only `super_admin` may change `role`
  itself. This runs regardless of what the browser's JavaScript does or
  whether RLS alone would have let the row through.
- Client-side guards (`guards.js`) exist purely for a fast, friendly
  redirect — they are not the security boundary.

## 9. Phase 2 (now included): payments & approval

Run `supabase/migrations/0002_payments.sql` in the SQL Editor after
0001 — it adds:

- **`student/payment.html`** — the "I Have Completed Payment" form.
  Optional payment reference/date/method/note, a required course
  selection, and an explicit warning never to enter a PIN, CVV, or
  banking password. Submits via the `submit_payment_confirmation`
  Postgres function, which can only ever set `payment_status` to
  `pending_verification` — never anything else.
- **`admin/payment-verification.html`** — lists every submission
  awaiting review with the student's name, Student ID (if already
  assigned), email, phone, course, and everything they submitted.
  **Confirm Payment** and **Reject Payment** call the
  `admin_confirm_payment` / `admin_reject_payment` functions, which
  atomically update the confirmation record, the student's profile
  (approving the account, activating enrollment, and assigning a
  `TIDEF-YYYY-NNNN` Student ID on confirm), write a
  `payment_approval_logs` audit entry, and create an in-app
  notification — all in one transaction, so there's no way to end up
  with a confirmed payment but an un-approved account, or vice versa.
- **Student ID generation** — `next_student_id()` uses an atomic
  upsert-based counter (`id_counters`, one row per year), so two admins
  confirming payments at the same moment can never be handed the same
  ID.
- Rejection **requires** a reason; the student sees it verbatim the next
  time they open `/student/payment.html` or `/student/pending-approval.html`.

**Security note:** the Phase 1 trigger that blocks students from
touching `payment_status`, `account_status`, `enrollment_status`, or
`student_id` is still fully in force. Phase 2 only opens one narrow,
specific exception: a student may move their own `payment_status` from
`not_submitted`/`rejected` to `pending_verification` — i.e. they can
_ask_ for review, never grant it. Only the two SECURITY DEFINER admin
functions above can move a payment to `confirmed`, and both check the
caller's role themselves before doing anything, independent of RLS.

### Try it end-to-end

1. As a test student: register → confirm email → you land on
   `pending-approval.html` → click **I Have Completed Payment** → fill
   the form → submit. You should land back on `pending-approval.html`
   showing **Pending Verification**.
2. As your super_admin account: go to **Payment Verification** in the
   sidebar → your test student should appear → click **View Details**
   to see everything they submitted → click **Confirm Payment**.
3. Back as the test student: refresh → you should now land on the real
   dashboard, with a Student ID showing in the format `TIDEF-2026-0001`.
4. Try the reject path too with a second test student, and confirm the
   rejection reason shows up on their side.

## 10. Phase 3 (now included): course management

Run `supabase/migrations/0003_courses.sql` in the SQL Editor after 0001
and 0002 — it adds `teacher_id`/`category`/`image_url`/`duration`/`level`
to `courses`, plus new `modules`, `lessons`, and `enrollments` tables.

- **`admin/courses.html`** — create a course (starts as `draft`),
  publish/unpublish, archive, and jump into the editor.
- **`admin/course-editor.html`** — three tabs: **Course Details** (name,
  category, description, duration, level, image, assigned teacher),
  **Curriculum** (add/remove modules and lessons — lesson content
  playback itself is Phase 4), and **Enrolled Students** (enroll an
  approved student, view/remove the roster).
- **`teacher/courses.html`** + **`teacher/course-editor.html`** — a
  teacher sees only their assigned course(s), can edit the description
  and manage curriculum, and can view (but not add/remove) their
  roster.
- **`student/courses.html`** + **`student/course.html`** — a student
  sees only courses they're actually enrolled in, and can view the
  curriculum structure. The dashboard's "My Courses" card is now real
  data instead of a placeholder.

**Design decision worth knowing about:** the spec says "admins and
authorized teachers" can create courses. I implemented it as _admin
creates and assigns a teacher; the teacher then manages that course's
content_ — matching how the rest of the admin-approval workflow works,
and how the sidebar/pages are already wired. If you'd rather let
teachers create their own courses outright, that's a small RLS + UI
change — say so and I'll adjust it before Phase 4.

**Security note:** curriculum protection follows the spec's public
course page rule (section 41) precisely — a published course's module
_titles_ are visible to anyone (curriculum preview), but full lesson
content is only visible to staff, the assigned teacher, or a student
with an active enrollment in that specific course. This is enforced by
RLS on the `lessons` table, not by hiding links in the UI.

### Try it end-to-end

1. As super_admin: **Courses → + New Course** → fill it in → **Publish**.
2. Register a second test account, promote it to `role = teacher` in
   the Table Editor → assign that teacher to the course from **Manage →
   Course Details**.
3. As the teacher: **My Courses → Manage Content** → add a module and a
   couple of lessons.
4. Back as super_admin: open the course → **Enrolled Students** tab →
   enroll your original test student.
5. As that student: **My Courses** should now show the course; opening
   it shows the modules/lessons the teacher just added.

## 12. Phase 4 (now included): the learning system

Run `supabase/migrations/0004_learning.sql` after 0001–0003. It adds
`lesson_progress`, `notes`, and `bookmarks`, plus the functions that
actually drive completion.

- **`student/course.html`** is now the real Course Learning Page from
  the spec: a sticky sidebar with every module/lesson and a ✓/●/○
  status icon, the current lesson in the main panel, a course-wide
  progress bar, Notes, a Bookmark toggle, and Previous/Next buttons.
- **Video lessons** embed the actual YouTube IFrame Player API (not
  just a thumbnail link). While playing, it reports progress to
  Supabase every 5 seconds, and again immediately on pause or end.
  `record_video_progress` tracks the **furthest point reached** — so
  seeking backward can't undo progress — and only flips a lesson to
  `completed` once **90% of its duration has actually been watched**,
  never just because the lesson was opened. That rule lives in the
  database function, not the UI, so it holds even if someone calls the
  API directly.
- **Text/PDF/external lessons** don't have a passive "watching" signal,
  so the student clicks **Mark as Complete** instead. The database
  function backing that button explicitly refuses to run on a `video`
  lesson — completion for video can only ever come from real watch
  progress.
- **Course progress** is computed as completed-lessons ÷ total-lessons
  and recalculated after every completion event; once every lesson in
  a course is done, the enrollment is automatically promoted to
  `completed` (this only promotes forward — adding a new lesson later
  won't un-complete someone).
- **Notes and bookmarks** are private per student per lesson —
  `student/bookmarks.html` lists everything saved, each linking
  straight back into that exact lesson.
- Curriculum editors (`admin/course-editor.html`,
  `teacher/course-editor.html`) now collect the actual lesson content
  when you add one — a YouTube URL for video, a text box for text
  lessons, a link for PDF/external — and can edit it afterward.

**A deliberate scope call:** `lesson_progress` stores the furthest
point reached per lesson, not a full timestamped watch-event log. That's
enough to drive the progress bar, the checkmarks, and correct
completion — a full analytics-grade event history is a bigger feature
that isn't needed for anything else in the spec, so I left it out
rather than over-build it. Worth flagging in case you want that level
of detail later (e.g. for a "time spent learning" report).

### Try it end-to-end

1. As the teacher (or admin): add a **video** lesson with a real
   YouTube URL, and a **text** lesson with some content.
2. As your enrolled test student: open the course, play the video —
   watch the sidebar dot go from ○ to ● to ✓ as you cross 90% watched
   (skipping ahead with the YouTube seek bar works too, since it
   reports current playback position). Try the text lesson's **Mark as
   Complete** button. Save a note, toggle a bookmark, and check
   `/student/bookmarks.html`.
3. Complete every lesson in the course and confirm the course card
   moves to a "completed" badge on `/student/courses.html`.

## 14. Phase 5 (now included): assignments & projects

Run `supabase/migrations/0005_assignments.sql` after 0001–0004. It adds
`assignments`, `submissions`, `projects`, and three private Storage
buckets (`assignment-files`, `submission-files`, `project-files`).

- **`teacher/assignments.html`** / **`admin/assignments.html`** — create
  an assignment (title, instructions, max marks, due date, whether
  resubmission is allowed after grading) and see every assignment
  across your course(s).
- **`teacher/assignment-grading.html`** / **`admin/assignment-grading.html`**
  (same file, works for either role) — every submission for one
  assignment, with the student's written answer and/or uploaded file,
  and a grade + feedback form. Grading is done through
  `grade_submission`, which refuses a grade outside `0..max_marks` and
  notifies the student automatically.
- **`student/assignments.html`** / **`student/assignment.html`** — see
  every assignment across enrolled courses with a live status badge
  (not submitted / submitted / graded), open one to read the
  instructions, submit a written answer and/or a file, and see the
  grade and feedback once graded. Resubmission is only offered when
  the assignment allows it or it hasn't been graded yet —
  `submit_assignment` enforces the same rule server-side regardless.
- **Projects** work a little differently from assignments, matching the
  spec: a student submits directly (title, description, file, GitHub
  link, live site link, screenshots) without a teacher having to create
  a project shell first. `student/projects.html` is both the
  submission form and the list of past submissions with grades/feedback;
  `teacher/projects.html` / `admin/projects.html` review and grade them.
- Files go into **private** Storage buckets — the database stores a
  path, never a public link, and the UI mints a short-lived signed URL
  only when a file actually needs to be opened or downloaded.
- Student dashboard's "Assignments Due" and teacher dashboard's
  "Students" / "Ungraded Submissions" are now live counts instead of
  placeholders.

**Design decisions worth knowing about:**

- A late submission isn't blocked server-side — the UI just flags it as
  "Overdue" if there's no submission past the due date. Say so if you'd
  rather hard-lock submissions after the deadline.
- One submission row per (assignment, student): resubmitting overwrites
  the previous answer/file and clears any existing grade, rather than
  keeping a full history of every attempt. `attempt_number` still
  increments, so you can see it's not their first try.

### Try it end-to-end

1. As the teacher: **Assignments → + New Assignment** for your course,
   with a due date and 100 max marks.
2. As your test student: **Assignments** → open it → submit a written
   answer and a file.
3. As the teacher: **Assignments → View Submissions** → grade it →
   confirm the student sees the grade/feedback and a notification.
4. As the student: **Projects → + Submit New Project** with a GitHub
   link and a screenshot; as the teacher, **Projects** should show it
   with a working "View" link to the screenshot and grade it.

## 16. Phase 6 (now included): quizzes & exams

Run `supabase/migrations/0006_quizzes.sql` after 0001–0005. It adds
`assessments`, `questions`, `question_options`, `assessment_attempts`,
and `attempt_answers`. Quizzes and exams share the same schema — an
assessment is just marked `kind = 'quiz'` or `kind = 'exam'`.

- **`teacher/quizzes.html`** / **`admin/quizzes.html`** — a tab toggle
  between Quizzes and Exams, create one (time limit, max attempts,
  passing score), and jump into the editor.
- **`teacher/quiz-editor.html`** / **`admin/quiz-editor.html`** (same
  file, works for either role) — add single-choice, true/false, or
  multi-answer questions, mark correct answers, edit settings, and view
  every student's attempts and pass/fail results.
- **`student/quizzes.html`** / **`student/exams.html`** — every
  quiz/exam across enrolled courses with attempts-used and best-score
  badges; **`student/quiz-attempt.html`** is the actual timed
  attempt — a countdown timer that auto-submits when it hits zero, and
  a confirm-before-submit on the manual path;
  **`student/quiz-results.html`** shows the score, pass/fail, and a
  full correct/incorrect breakdown per question.

**The one rule your spec called out explicitly here — "students must
not be able to modify their results" — holds structurally, not by
convention:** `assessment_attempts` and `attempt_answers` have **no
INSERT or UPDATE policy at all**. The only way data gets into those
tables is through `start_attempt()` and `submit_attempt()`, two
SECURITY DEFINER functions that ignore whatever the client claims and
compute the actual grade server-side by comparing submitted option IDs
against the real `question_options.is_correct` column — which students
can never read directly either (RLS denies it outright; they receive
questions through `get_attempt_questions()`, which strips that column
before it ever reaches the browser). `submit_attempt` also flatly
refuses to run twice on the same attempt.

**Automatic submission (spec section 26)** works two ways: while the
tab is open, a client-side timer calls `submit_attempt` the instant it
hits zero. If someone closes the tab mid-attempt instead, the next time
they (or `start_attempt`) touch that assessment, the abandoned attempt
is detected as past its time limit and auto-closed at a zero score
before a new attempt is allowed — no background cron job needed.

**A design call worth knowing about:** multi-answer questions are
graded all-or-nothing — a student needs to select the _exact_ correct
set to earn any points, no partial credit for getting some right. Say
so if you'd rather award partial credit per correct option selected.

### Try it end-to-end

1. As the teacher: **Quizzes & Exams → Quizzes tab → + New Quiz**, set
   a 2-minute time limit and 2 attempts, then **Manage** it → add a
   couple of questions of different types, marking correct answers.
2. As your test student: **Quizzes → Start** → answer and submit before
   time runs out → check the results/review page shows the right
   correct/incorrect marks.
3. Start it again and just let the timer hit zero without submitting —
   confirm it auto-submits and scores whatever was left unanswered as
   wrong.
4. As the teacher: open the quiz's **Results** tab and confirm both
   attempts show up with the right scores.

## 18. Phase 7 (now included): community

Run `supabase/migrations/0007_community.sql` after 0001–0006. It adds
two independent features, matching the spec's two sections:

- **Course/lesson Q&A** (`qa_threads`, `qa_replies`) — `student/questions.html`
  lets a student pick a course and, optionally, a specific lesson, and
  ask a question with an attached file/image; `student/question-thread.html`
  is the reply thread. The same thread page is reused under
  `/teacher/` and `/admin/` (role-aware — same file, different sidebar)
  so a teacher or admin can answer and moderate. **Only the original
  asker, or a teacher/admin, can mark a reply "Accepted"** — enforced
  by the `accept_reply` function, which also atomically un-accepts any
  previous answer so a thread only ever has one. Opening a lesson in
  the Course Learning Page now has a one-click "Ask a Question" link
  that pre-fills the course and lesson.
- **Platform-wide community feed** (`posts`, `post_comments`,
  `post_likes`) — `student/community.html` is a simple social feed open
  to any approved member (student, teacher, or admin): post text and an
  optional image, like, and comment. This one is deliberately **not**
  scoped to a course, matching the spec's separate "Student Community"
  section — it's a general space, not tied to enrollment in anything
  specific. `admin/community.html` is the same feed with moderation
  rights; any teacher or admin can delete any post or comment, not just
  their own — RLS enforces that directly, not just the UI.

**Security note:** neither feature lets someone read content from a
course they're not enrolled in (Q&A) or an unapproved account
participate (community) — both checked in RLS, not just hidden in the
UI.

### Try it end-to-end

1. As your test student: open a lesson in a course → **Ask a Question**
   → confirm it lands on `student/questions.html` with the course and
   lesson already selected → submit.
2. As the teacher: **Q&A** → open it → reply → as the student, mark
   that reply **Accepted** → confirm the thread now shows "Resolved".
3. As the student: **Community** → post something with an image →
   like it from a second test account → add a comment → confirm the
   counts update live.
4. As admin: **Community** → delete someone else's post, confirming
   moderation works regardless of who posted it.

## 20. Phase 8 (now included): certificates

Run `supabase/migrations/0008_certificates.sql` after 0001–0007. It
adds `certificates`, a sequential certificate-number counter, and a
public verification function.

- **`admin/certificates.html`** — an "Eligible for Certificate" list
  surfaces every student whose `enrollments.status` is already
  `completed` (set automatically back in Phase 4) but who doesn't have
  a certificate yet. Clicking one opens an upload form; `issue_certificate`
  generates a sequential `TIDEF-CERT-YYYY-NNNN` number, stores the file,
  and notifies the student, all as one transaction.
- **`student/certificates.html`** — every certificate a student has,
  with a download link. The student dashboard now shows a certificates
  preview card too, matching the spec's "displayed on student
  dashboard" line directly.
- **`verify-certificate.html`** (public, no login, at the site root) —
  anyone can enter a certificate number and confirm it's genuine: name,
  course, and issue date. This deliberately does **not** expose the
  certificate file itself to an anonymous visitor — verification
  confirms authenticity, it doesn't hand out the document. Matches the
  "Cert/Verify" link already present in your live site's navigation.

**A small bonus while I was in this area:** `student/id-card.html` was
a dead link ever since Phase 1 (it was in the nav from the start, per
your spec's structure, but nothing built it yet). It needed no new
backend — it's a print-styled digital ID card built entirely from data
that already exists (`student_id`, name, course, status), with a
"Print / Save as PDF" button. Flagging this since it's slightly outside
Phase 8's own scope, even though it's a two-line addition.

### Try it end-to-end

1. Make sure your test student has a `completed` enrollment (finish
   every lesson in a course, from Phase 4's test).
2. As admin: **Certificates** → they should appear under "Eligible" →
   issue one with any PDF/image file.
3. As the student: **Certificates** (and the dashboard) should show it
   with a working download link, and a notification should have
   arrived.
4. Open `verify-certificate.html` in a private/incognito window (no
   login) and enter that certificate number — confirm it verifies.
5. Check `/student/id-card.html` renders and prints cleanly.

## 21. Phase 9 (now included): admin & reporting

Run `supabase/migrations/0009_admin.sql` after 0001–0008. It's
deliberately small — most of what this phase needs was already
enforced back in Phase 1's `protect_privileged_fields` trigger (an
admin can already change `account_status`, and only a `super_admin`
can change `role`, through plain table updates). This migration only
adds what was genuinely missing: an audit trail and a settings table.

- **`admin/users.html`** — search/filter every account by role, change
  a role (Super Admin only — the dropdown is disabled for a plain
  Admin, and the underlying trigger would reject the attempt anyway if
  someone bypassed the UI), suspend/reactivate any account.
- **`admin/students.html`** — the fuller student roster from spec
  section 15: account status, payment status, search, suspend/reactivate.
- **`admin/teachers.html`** — every teacher and the course(s) they're
  assigned to, read-only (promoting someone to teacher happens on the
  Users page).
- **`admin/activity-logs.html`** — the most recent 100 admin actions:
  role changes, suspensions/reactivations, settings updates. Payment
  confirm/reject already had its own detailed audit trail since Phase 2
  (`payment_approval_logs`) — this is the general-purpose one for
  everything else.
- **`admin/settings.html`** — a small number of real site settings
  (site name, support phone/email). Not just a form for show: the
  suspended-account screen (`student/pending-approval.html`) now reads
  the support phone from here live instead of a hardcoded number.
- **`admin/reports.html`** — enrollment and completion per course, an
  overall quiz/exam pass rate, and assignment-grading throughput, drawn
  from real data across every phase so far. Rendered as simple CSS bar
  visualizations rather than pulling in a charting library — consistent
  with the rest of the build having zero external JS dependencies
  beyond the Supabase SDK itself.

### Try it end-to-end

1. As super_admin: **Users & Roles** → search for your test teacher
   account → confirm the role dropdown is enabled and works.
2. Log in as a plain `admin` (if you have one) and confirm that same
   dropdown is disabled, while Suspend/Reactivate still works.
3. **Students** → suspend your test student → confirm they get signed
   out to the login page next time they load a guarded page, and that
   the suspended screen shows your real support phone from Settings.
4. **Settings** → change the support phone → reactivate the student →
   suspend them again → confirm the new number shows up.
5. **Activity Logs** → confirm every action above appears with the
   right actor name and timestamp.
6. **Reports** → confirm the numbers roughly match what you'd expect
   from your test data.

## 22. Where things stand

Phases 1–9 are built. What's left from the original 60-section spec,
roughly in the order I'd tackle it:

- **Attendance** (spec section 28) — not yet built.
- **Learning streaks & badges** (sections 38–39) — not yet built.
- **Search across the LMS** (section 34) beyond what each page already
  has (course/student search exist; a global search bar doesn't).
- **Calendar** (section 35) — deadlines exist as data (assignment
  `due_at`, exam scheduling) but there's no unified calendar view yet.
- **Announcements** (section 29, nav link already present) — broadcast
  messages from admin to students/teachers.
- **Course reviews** (section 40).
- **Public course pages** (section 41) — marketing-facing course
  detail pages for visitors who haven't registered yet.
- **Final integration testing** (the original Phase 10) — a full
  pass through every user flow together, ideally by you on a real
  deployment now that Phases 1–9 exist to test as a whole.

Say which of these matters most for TIDEF ITECH's actual launch and
I'll build it next — or if Phase 10-style testing is more valuable
right now than more features, that's a completely reasonable place to
pause and consolidate instead.
