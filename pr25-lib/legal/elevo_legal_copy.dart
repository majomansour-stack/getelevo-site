// Attorney review: a lawyer has not reviewed these Terms or this Privacy
// Policy. Have a qualified attorney review them before launch. Do not show a
// draft banner on the screen.

/// Public support address already used by the landlord More screen.
const elevoSupportEmail = 'hello@getelevo.app';

/// Confirmed legal name of the operator.
const elevoLegalEntityName = 'ELEVO Property Management LLC';

const elevoLegalEffectiveDate = 'November 21, 2026';

class ElevoLegalSection {
  const ElevoLegalSection(this.title, this.body);
  final String title;
  final String body;
}

const elevoTermsSections = <ElevoLegalSection>[
  ElevoLegalSection(
    '1. Who this covers',
    'These terms are between you and $elevoLegalEntityName ("Elevo", "we"). '
        'They cover the Elevo app and the public terms and privacy pages. '
        'They take effect on $elevoLegalEffectiveDate. '
        'Questions go to $elevoSupportEmail.',
  ),
  ElevoLegalSection(
    '2. Who Elevo is for',
    'Elevo is for landlords, tenants, and vendors or contractors. '
        'It is built for residential property in Arizona, in the United States. '
        'When a landlord adds a property, the state is Arizona and the form does not let them pick another state. '
        'You must be at least 18 years old. Elevo is not for children. '
        'Sign-up does not ask for a date of birth.',
  ),
  ElevoLegalSection(
    '3. What Elevo does, and what it does not',
    'Elevo is software for tracking rent, repairs, documents, and messages in one place. '
        'Elevo is not a party to a lease, a sale, or a repair contract. '
        'Elevo does not employ vendors, does not run background checks on them, and does not guarantee their work. '
        'A preferred-partner listing can be reviewed before it is shown. That review is not a promise that the vendor is qualified or trustworthy. '
        'Elevo does not give legal, tax, or financial advice, including advice about Arizona eviction or lease language. '
        'The landlord More screen may show a separate real-estate contact. That person is not Elevo, and Elevo is not your broker.',
  ),
  ElevoLegalSection(
    '4. Rent and deposits',
    'Elevo does not collect, hold, or process rent or security deposits. '
        'A landlord lists the ways they prefer to be paid, such as Zelle, Venmo, a bank transfer, a check, or cash. '
        'The tenant pays the landlord directly, outside Elevo. '
        'When a tenant taps I Have Paid, and when a landlord confirms that payment, Elevo only saves a record. '
        'That record is not a payment, and it does not prove the money moved.',
  ),
  ElevoLegalSection(
    '5. Landlord plans',
    'Landlords can pay Elevo for a plan. The prices on the subscription screen are: '
        'Essential, \$39.99 a month or \$299 a year; '
        'Unlimited, \$79 a month or \$699 a year; '
        'Done for You setup, \$249 once; '
        'an extra property on Essential, \$12.99 a month. '
        'Essential is 1 property. '
        'Each extra property is \$12.99 a month. '
        'Unlimited has no property limit while the subscription is active. '
        'Tenants are not charged to use Elevo. '
        'After you confirm your email, you choose Essential or Unlimited before the landlord app opens. '
        'That choice opens Stripe and collects a card. The card is not charged that day. '
        'It is charged automatically when the 7-day trial ends unless you cancel first. '
        'After that, Stripe renews the plan until you cancel. '
        'Manage Subscription opens the Stripe billing portal, where you can change the card or cancel. '
        'When the trial date has passed and there is no paying plan, or when Stripe marks the subscription past due, canceled, unpaid, or incomplete, Elevo blocks adding another property. Everything already saved stays readable. '
        'Deleting an Elevo account turns off the login and clears the contact details. It does not remove a property, unit, or payment instruction other people still need. Deleting the account cancels the Stripe subscription immediately. There is no refund for the current period. '
        'Done for You, as the app describes it, is a one-time setup of properties, documents, tenant invitations, and a one-hour onboarding call. '
        'The app says Elevo will reach out within one business day after you pay. '
        'A landlord can share one referral code. A new landlord may enter that code. '
        'Both then receive 20% off for 3 months. The new landlord still adds a card for the 7-day trial. '
        'The discount applies to the subscription, including after the trial ends.',
  ),
  ElevoLegalSection(
    '6. Vendor plans',
    'Vendors can pay for a listing. The monthly prices on the vendor plan screen are Basic \$39.99, Featured \$89.99, Preferred \$149, and Platinum \$199. '
        'The app does not show a yearly vendor price. '
        'Choosing a higher plan opens a Stripe checkout page and charges the new price then. '
        'Choosing a lower plan asks you to confirm, then opens the Stripe billing portal. Elevo does not change the vendor plan by itself. '
        'The screen says a downgrade waits until the end of the billing period, with no refund for unused time. '
        'Preferred and Platinum can be marked full. A full plan offers a waitlist and does not charge until a spot is confirmed.',
  ),
  ElevoLegalSection(
    '7. Tenant screening',
    'Screening uses the landlord\'s own RentSpree account. '
        'The landlord saves their RentSpree link in Elevo, and applicants open that link. '
        'Elevo is not part of RentSpree and is not affiliated with it. '
        'Elevo does not receive or store the RentSpree credit report. The applicant pays RentSpree, not Elevo. '
        'Elevo can store notes the landlord types, and the notes box invites a credit score or a concern. Those notes are the landlord\'s words, not a report from RentSpree. '
        'The landlord, not Elevo, is responsible for the Fair Credit Reporting Act and for fair housing laws, including Arizona law.',
  ),
  ElevoLegalSection(
    '8. Your account',
    'You agree to give a current name, email, and phone, and to keep your password to yourself. '
        'Elevo emails you a confirmation link, and the account is not ready until you open it. '
        'A tenant is not linked to a unit until that email is confirmed. '
        'You are responsible for what happens under your account. '
        'If you think someone else signed in, email $elevoSupportEmail. '
        'Elevo does not offer two-factor sign-in.',
  ),
  ElevoLegalSection(
    '9. Your responsibilities',
    'You will follow the law that applies to you, including landlord-tenant law, fair housing law, and any license you need to do repair work. '
        'You will not use Elevo to break the law, to harass someone, or to upload a file you have no right to store.',
  ),
  ElevoLegalSection(
    '10. Changes to these terms',
    'We may update these terms. The date at the top of this page will change in the app and on the public terms page. '
        'If you keep using Elevo after that date, you agree to the update. '
        'We do not send a separate email for every wording change.',
  ),
  ElevoLegalSection(
    '11. Arizona law',
    'These terms are governed by the laws of the State of Arizona and the United States. '
        'Disputes are handled in the state or federal courts in Arizona. '
        'If you are a consumer, you may also have rights that these terms cannot take away.',
  ),
  ElevoLegalSection('12. Contact', 'Email $elevoSupportEmail.'),
];

const elevoPrivacySections = <ElevoLegalSection>[
  ElevoLegalSection(
    '1. Who we are',
    '$elevoLegalEntityName ("Elevo") provides the Elevo app. '
        'This policy takes effect on $elevoLegalEffectiveDate. '
        'To ask about your information, email $elevoSupportEmail.',
  ),
  ElevoLegalSection(
    '2. Information we collect',
    'Account information: name, email, phone, and role (landlord, tenant, or vendor). '
        'A vendor can also enter a company name, service area, and license. '
        'Your password is handled by the sign-in service. We do not see the password itself. '
        'Property and unit information: the address, city, Arizona as the state, rent, deposits recorded as amounts, lease dates, and the tenant name and email when a landlord invites them. '
        'Messages, including one-to-one messages and group repair chats. '
        'Photos and documents you upload, including repair photos, leases, invoices, and files in the landlord private vault. '
        'Rent records: the payment methods a landlord lists, and the record created when someone marks rent as paid or confirms it. Elevo does not collect the rent money or the deposit. '
        'Screening: the applicant details a landlord enters, and the landlord\'s own notes. Elevo does not receive the RentSpree credit report. '
        'One Firebase Cloud Messaging device token per person, stored in push_subscriptions, so Elevo can send a push notification. Notification settings cover push and email. Elevo does not send text messages. '
        'Subscription information: the plan name and the trial end date saved on the account. Card numbers are typed on Stripe\'s pages, not in Elevo.',
  ),
  ElevoLegalSection(
    '3. Who handles the information',
    'Supabase stores the database, the files, and the sign-in accounts. '
        'Stripe handles landlord and vendor subscription checkout. Elevo opens Stripe\'s payment page and does not store the card number. '
        'Firebase Cloud Messaging delivers push notifications. '
        'Resend sends email, such as a welcome message or a tenant invitation, through a function on Supabase. '
        'RentSpree handles screening on its own site. Elevo is not affiliated with RentSpree and does not receive the credit report. '
        'We do not sell personal information. We do not show ads.',
  ),
  ElevoLegalSection(
    '4. Who can see it',
    'A landlord can see their own properties, units, tenants, messages for those units, documents, private vault, rent records, and repairs. '
        'A tenant can see the unit they currently rent, the landlord\'s payment instructions, their messages, their repairs, and documents the landlord shared for that tenancy. '
        'After the tenant moves out, they no longer see new messages, new files, or new repairs for that unit. '
        'A vendor can see repairs assigned to them and the repair chat while they are assigned. '
        'If the landlord assigns someone else, the first vendor can still see messages from the time they were on the job, not messages from after they left. '
        'The private vault is visible to that landlord. Tenants do not see it. '
        'People who operate Elevo can access the database to run and support the service. We do not use that access to sell your information.',
  ),
  ElevoLegalSection(
    '5. Children',
    'Elevo is not for anyone under 18. We do not knowingly collect personal information from anyone under 18. '
        'Sign-up does not ask for a birthday. If you believe a child has an account, email $elevoSupportEmail and we will delete it.',
  ),
  ElevoLegalSection(
    '6. How long we keep it',
    'We keep information while the account is open. There is no automatic deletion date. '
        'Landlords, tenants, and vendors can delete an account in the app. After a confirmation, Elevo turns off that login and clears the name, email, and phone. The account row stays, so a property, unit, or payment instruction is not removed. '
        'Elevo also deletes notification settings, the Firebase device-token row, emergency contacts, and the private vault, and it removes storage files that are only theirs. '
        'Records other people still need are kept. That includes properties, units, rent instructions, repairs, documents, photo logs, and messages. '
        'Your name is removed from a tenancy, a repair you filed, a payment record, and message headers where the app can do that. The message text stays for the other people in the conversation. '
        'A landlord\'s payment instructions, including bank details they typed for tenants, stay so current tenants can still pay. '
        'Stripe webhook audit rows are kept. Deleting the account cancels the Stripe subscription immediately. There is no refund for the current period. '
        'You can also email $elevoSupportEmail and ask us to delete the account or send a copy of what we hold.',
  ),
  ElevoLegalSection(
    '7. A copy of your information',
    'There is no button in the app to download everything we hold. '
        'Email $elevoSupportEmail and ask for a copy. We will send what we have for your account.',
  ),
  ElevoLegalSection(
    '8. Security',
    'Sign-in is provided by Supabase. Repair photos and other private files are stored in private storage and opened with a short-lived link, not a public web address. '
        'Access rules limit each person to their own properties, tenancy, or assigned jobs. '
        'No storage method is perfect. We do not promise that Elevo cannot be broken into. Two-factor sign-in is not available.',
  ),
  ElevoLegalSection(
    '9. Changes and contact',
    'We may update this policy. The date at the top will change in the app and on the public privacy page. '
        'Email $elevoSupportEmail with questions.',
  ),
];
