-- Store the Google Drive passport view URL in the existing profile photo field.
-- The URL is supplied through signup metadata after the Apps Script upload.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (
    id, full_name, email, phone, dob, gender, address,
    interested_course_id, profile_photo_url
  )
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.email,
    new.raw_user_meta_data ->> 'phone',
    nullif(new.raw_user_meta_data ->> 'dob', '')::date,
    new.raw_user_meta_data ->> 'gender',
    new.raw_user_meta_data ->> 'address',
    nullif(new.raw_user_meta_data ->> 'interested_course_id', '')::uuid,
    new.raw_user_meta_data ->> 'passport_url'
  );
  return new;
end;
$$;
