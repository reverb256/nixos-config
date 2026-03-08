# Marketing Skills Consolidation Master Specification

**Overview**: Consolidate 30+ marketing skills into 8 category-based skills
**Created**: 2026-03-07
**Status**: Specification ready for implementation

---

## Consolidation Map

| New Skill | Source Skills (Remove) | Count |
|-----------|----------------------|-------|
| `marketing:seo` | ai-seo, programmatic-seo, schema-markup, site-architecture | 4→1 |
| `marketing:cro` | page-cro, signup-flow-cro, popup-cro, onboarding-cro, paywall-upgrade-cro, form-cro | 6→1 |
| `marketing:content` | copywriting, copy-editing, content-strategy, social-content, ux-writing | 5→1 |
| `marketing:growth` | launch-strategy, referral-program, pricing-strategy, viral-loops | 4→1 |
| `marketing:outbound` | cold-email, email-sequence, sales-enablement, paid-ads, ad-creative | 5→1 |
| `marketing:analytics` | churn-prevention, revops, analytics-tracking, business-intelligence | 4→1 |
| `marketing:product` | ai-product-strategy, product-marketing-context, competitor-alternatives, ab-test-setup | 4→1 |
| `marketing:psychology` | marketing-psychology, fogg-behavior-model, free-tool-strategy | 3→1 |

**Total**: 35 source skills → 8 consolidated skills

---

## 1. marketing:seo

### Skill Manifest
```yaml
name: marketing:seo
description: Complete SEO expertise including AI-powered SEO, programmatic SEO, schema markup, and site architecture.

triggers:
  - "SEO for..."
  - "Improve search ranking..."
  - "Schema markup for..."
  - "Site structure for SEO..."
  - "Programmatic SEO..."
```

### Content Structure

#### 1.1 AI-Powered SEO
- Content optimization using AI
- Keyword research with AI assistance
- SERP analysis automation
- Content gap identification

#### 1.2 Programmatic SEO (pSEO)
- Page template generation
- Database-driven content
- Scalable page creation
- Quality maintenance at scale

#### 1.3 Schema Markup
```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "Article Title",
  "author": {
    "@type": "Person",
    "name": "Author Name"
  },
  "datePublished": "2024-01-01",
  "dateModified": "2024-01-01"
}
```

Common Schema Types:
- Article, BlogPost, NewsArticle
- Product, Offer, AggregateRating
- LocalBusiness, Organization
- FAQPage, HowTo
- VideoObject, BreadcrumbList

#### 1.4 Site Architecture for SEO
```
Example Structure:
/
├── /products/           # Category pages
│   ├── /category-a/     # Subcategories
│   └── /category-b/
├── /blog/              # Content hub
│   ├── /topic-a/
│   └── /topic-b/
├── /about/             # Trust signals
└── /contact/           # Conversion point
```

Best Practices:
- Flat architecture (max 3 clicks from home)
- Internal linking strategy
- Canonical URLs
- XML sitemaps
- Robots.txt optimization

---

## 2. marketing:cro

### Skill Manifest
```yaml
name: marketing:cro
description: Complete conversion rate optimization expertise including page CRO, signup flows, popups, onboarding, paywalls, and forms.

triggers:
  - "Improve conversions..."
  - "Optimize signup flow..."
  - "Reduce churn..."
  - "Increase signups..."
  - "Form optimization..."
```

### Content Structure

#### 2.1 Page CRO Framework

**AIDA Model Applied to Landing Pages**:
1. **Attention**: Hero section, compelling headline
2. **Interest**: Benefits, social proof
3. **Desire**: Features, testimonials, case studies
4. **Action**: Clear CTAs with urgency

**Key Elements**:
- Above-the-fold value proposition
- Benefit-focused copy (not features)
- Social proof (testimonials, logos, counts)
- Clear single CTA per section
- Trust badges and guarantees

#### 2.2 Signup Flow Optimization

**Best Practices**:
- Minimize form fields (progressive profiling)
- Social login options
- Clear value at each step
- Progress indicators for multi-step
- Email validation (not confirm step)
- Guest checkout option

**Exit Intent Popups**:
- Trigger: Mouse leaving viewport
- Offer: Lead magnet, discount, content
- Timing: After 30 seconds on site
- Frequency: Once per session

#### 2.3 Onboarding CRO

**User Activation Checklist**:
- [ ] First value achieved in <5 minutes
- [ ] Progressive disclosure of features
- [ ] Contextual tooltips
- [ ] Empty states with clear next actions
- [ ] Celebrate milestones

#### 2.4 Paywall Optimization

**Models**:
- **Hard Paywall**: Metered articles (N+1)
- **Soft Paywall**: Preview content, subscribe for full
- **Dynamic Paywall**: Based on engagement, referral source

**Optimization Elements**:
- Preview length optimization
- Offer presentation at natural break points
- Bundle options (monthly/annual/lifetime)
- Social proof near paywall
- Money-back guarantee callout

#### 2.5 Form Optimization

**Best Practices**:
- Top-aligned labels
- Inline validation (not after submit)
- Clear error messages with fixes
- Save for later / progress save
- Multi-step for long forms
- Estimated completion time

**Field Reduction**:
```markdown
- Name → Split First/Last only if needed
- Email → Essential
- Phone → Remove unless calling required
- Company → Only if B2B
- Address → After conversion confirmed
```

---

## 3. marketing:content

### Skill Manifest
```yaml
name: marketing:content
description: Complete content marketing expertise including copywriting, editing, strategy, social content, and UX writing.

triggers:
  - "Write copy for..."
  - "Content strategy for..."
  - "Social media content..."
  - "UX writing for..."
  - "Review/edit this content..."
```

### Content Structure

#### 3.1 Copywriting Frameworks

**PAS Formula**:
- **Problem**: Identify pain point
- **Agitation**: Make it emotional
- **Solution**: Present your product

**BAB Formula**:
- **Before**: Current state
- **After**: Desired state
- **Bridge**: Your product

**4 U's**:
- **Urgent**: Why now?
- **Unique**: What's different?
- **Useful**: What's the benefit?
- **Ultra-specific**: Precise details

#### 3.2 Content Strategy

**Content Pillars**:
```
1. Educational (How-to, guides)
2. Entertaining (Stories, humor)
3. Inspirational (Case studies, success stories)
4. Promotional (Product announcements, offers)
```

**Content Calendar Template**:
| Date | Type | Topic | CTA | Distribution |
|------|------|-------|-----|--------------|
| Mon | Educational | How to X | Read more | Blog, Newsletter |
| Wed | Promotional | Product launch | Shop now | Email, Social |
| Fri | Entertainment | Customer story | Share | Social |

#### 3.3 Social Content

**Platform Best Practices**:
- **Twitter/X**: Short, timely, threads, images
- **LinkedIn**: Professional, insights, long-form
- **Instagram**: Visual, stories, reels
- **TikTok**: Raw, trending, educational
- **YouTube**: Search-based, how-to, series

**Content Buckets**:
1. Educational (60%)
2. Entertaining (20%)
3. Promotional (10%)
4. Engagement (10%)

#### 3.4 UX Writing

**Principles**:
- Clear over clever
- Active voice
- Specific numbers ("Save 2 hours" not "Save time")
- User-centered language
- Front-load important info

**Button Copy Examples**:
| Bad | Good |
|-----|------|
| Submit | Create account |
| OK | Got it |
| Learn more | See how it works |
| Buy now | Get started - $9/mo |

---

## 4. marketing:growth

### Skill Manifest
```yaml
name: marketing:growth
description: Complete growth marketing expertise including launch strategies, referral programs, pricing strategy, and viral loops.

triggers:
  - "Launch strategy for..."
  - "Build referral program..."
  - "Pricing for..."
  - "Viral growth for..."
```

### Content Structure

#### 4.1 Launch Strategy

**Pre-Launch Checklist** (8 weeks out):
- [ ] Build waitlist/landing page
- [ ] Content pipeline (blog posts, guest posts)
- [ ] Outreach list (journalists, influencers)
- [ ] Beta tester recruitment
- [ ] ProductHunt listing prepared
- [ ] Press kit (screenshots, logos, boilerplate)
- [ ] Demo video (60-90 seconds)

**Launch Week Plan**:
| Day | Channel | Activity |
|-----|---------|----------|
| -7 | Email | Warm waitlist, calendar hold |
| -1 | Social | Teasers, countdown |
| 0 | PH | ProductHunt launch |
| 0 | Social | Announcement, demo |
| +1 | Email | Follow-up, social proof |
| +7 | Blog | Launch recap learnings |

#### 4.2 Referral Programs

**Program Types**:
- **Two-sided incentives**: Both parties rewarded (Dropbox)
- **One-sided**: Referrer rewarded only
- **Tiered**: Increasing rewards for more referrals
- **Gamified**: Leaderboards, badges

**Best Practices**:
```javascript
// Reward structure example
{
  tiers: {
    1: { referrals: 1, reward: "$10 credit" },
    2: { referrals: 5, reward: "$50 credit" },
    3: { referrals: 10, reward: "$150 credit + feature unlock" }
  },
  rewards: {
    referrer: "Account credit",
    referee: "20% discount first purchase"
  }
}
```

#### 4.3 Pricing Strategy

**Models**:
1. **Freemium**: Free tier + paid upgrades
2. **Tiered**: Good/Better/Best
3. **Usage-based**: Pay per unit
4. **Platform + Usage**: Base + variable

**Pricing Page Best Practices**:
- 3-4 tiers max
- Highlight recommended tier
- Clear feature comparison
- Monthly/annual toggle (annual 20% off)
- FAQ below pricing
- Social proof

**Psychological Pricing**:
- Charm pricing: $9 vs $10
- Anchor pricing: Show $99 first, then $49
- Bundle pricing perceived as better value

#### 4.4 Viral Loops

**Viral Coefficient (K-factor)**:
```
K = (number of invitations sent) × (conversion rate)

Target: K > 1 for viral growth
Example: 5 invitations × 25% conversion = K = 1.25
```

**Loop Elements**:
1. Trigger: When to prompt sharing
2. Action: Easy sharing mechanism
3. Reward: Incentive for both parties
4. Visibility: See referrals/activity

---

## 5. marketing:outbound

### Skill Manifest
```yaml
name: marketing:outbound
description: Complete outbound marketing expertise including cold email, email sequences, sales enablement, paid advertising, and ad creative.

triggers:
  - "Cold email for..."
  - "Email sequence for..."
  - "Sales deck for..."
  - "Run ads for..."
  - "Ad creative for..."
```

### Content Structure

#### 5.1 Cold Email Framework

**Subject Line Formulas**:
- "[Company Name] + [Benefit]"
- "Question about [pain point]"
- "Quick question"
- "[Prospect's company] + [competitor]"

**Email Structure**:
```
1. Hook: Personalized opening (research-based)
2. Problem: Agitate known pain point
3. Value: Brief value prop (2-3 sentences)
4. Proof: Social proof, case study
5. CTA: Low-friction question
```

**Example**:
```
Subject: Quick question about [company]

Hi [Name],

Saw your post about [topic] - great insights on [specific point].

Many [role] at [company size] companies tell us [pain point].

[Company] helps [prospect] achieve [outcome] in [timeframe].

[Similar company] saw [metric] improvement using our approach.

Would you be opposed to a 10-min call next week?
```

#### 5.2 Email Sequences

**Drip Campaign Structure**:
| Email | Focus | Timing |
|-------|-------|--------|
| 1 | Value, no pitch | Day 0 |
| 2 | Problem agitation | Day 2 |
| 3 | Case study | Day 4 |
| 4 | Soft pitch | Day 7 |
| 5 | Breakup / final value | Day 14 |

**Best Practices**:
- Personalize beyond {FirstName}
- One clear CTA per email
- Mobile-optimized
- Plain text + HTML versions
- Track opens/clicks (respect privacy)

#### 5.3 Sales Enablement

**One-Pager Structure**:
```
1. Headline: Problem solved
2. Subhead: For [ICP]
3. Benefits (not features): 3-5 bullets
4. Social proof: Logos, metrics
5. How it works: 3-step visual
6. Pricing: Starting at
7. CTA: Clear next step
```

**Battle Cards** (for sales team):
| Competitor | Our Advantage | Response to "Why them?" |
|------------|---------------|------------------------|
| Competitor A | We have X feature | X means benefit Y |
| Competitor B | We're faster | Speed = time saved |

#### 5.4 Paid Ads

**Channel Selection**:
| Channel | Best For | B2B/B2C |
|---------|----------|---------|
| Google Search | High intent | Both |
| LinkedIn Ads | B2B targeting | B2B |
| Meta (FB/IG) | Awareness | B2C |
| TikTok | Gen Z | B2C |
| Reddit | Niche communities | Both |

**Ad Copy Formula**:
```
Headline: [Benefit] in [Timeframe]
Body: For [target audience] who [pain point],
[product] provides [benefit].
CTA: [Action] to get [outcome]
```

#### 5.5 Ad Creative Best Practices

**Image/Video Specs**:
- **Facebook Feed**: 1200x628, <20% text
- **Instagram Feed**: 1080x1080 (square)
- **Stories**: 1080x1920 (9:16)
- **LinkedIn**: 1200x627

**Creative Testing**:
```markdown
Test Matrix:
- A: Headline variations (3-5)
- B: Image variations (3-5)
- C: CTA variations (2-3)
- D: Audience segments (3-5)

Total combinations: 90-375 ads
Start with 3-3-2-3 = 54 ad variations
```

---

## 6. marketing:analytics

### Skill Manifest
```yaml
name: marketing:analytics
description: Complete marketing analytics expertise including churn prevention, revenue operations, analytics tracking, and business intelligence.

triggers:
  - "Reduce churn..."
  - "Set up analytics..."
  - "Track conversions..."
  - "Dashboard for..."
  - "Revenue insights..."
```

### Content Structure

#### 6.1 Analytics Tracking Setup

**Key Events to Track**:
```javascript
// Page views
gtag('event', 'page_view', { page_title, page_location })

// Engagement
gtag('event', 'engagement', { content_type, content_id })

// Conversions
gtag('event', 'purchase', { transaction_id, value, currency })

// Custom events
gtag('event', 'custom_event', { custom_param })
```

**Funnel Tracking**:
```
1. Landing page view
2. CTA click
3. Sign-up start
4. Email confirmation
5. Activation (first key action)
6. Purchase
```

#### 6.2 Churn Prevention

**Churn Prediction Signals**:
- Decreased login frequency
- Reduced feature usage
- Support ticket increase
- Payment issues
- Competitor engagement

**Intervention Framework**:
```
Risk Level | Trigger | Action
-----------|---------|--------
Low | -30% usage | Automated email with tips
Medium | -60% usage | Personal outreach
High | -80% usage | Executive outreach, offers
Lost | Churned | Win-back campaign
```

#### 6.3 Revenue Operations (RevOps)

**Metrics Dashboard**:
- MRR/ARR
- Growth rate (MoM, YoY)
- Churn rate (logo, revenue)
- Net revenue retention (NRR)
- Customer acquisition cost (CAC)
- Lifetime value (LTV)
- LTV:CAC ratio
- Sales cycle length

**NRR Formula**:
```
NRR = (Starting MRR + Expansion - Downsell - Churn) / Starting MRR

Target: >100% (growing existing customers)
Good: 110%+
Excellent: 125%+
```

#### 6.4 Business Intelligence

**Dashboard Layers**:
1. **Executive**: High-level KPIs, trends
2. **Manager**: Team metrics, funnel analysis
3. **Individual**: Activity metrics, goals

**Report Types**:
- Real-time dashboards (monitoring)
- Weekly reports (tactical)
- Monthly reports (strategic)
- Quarterly reviews (planning)

---

## 7. marketing:product

### Skill Manifest
```yaml
name: marketing:product
description: Complete product marketing expertise including AI product strategy, product marketing context, competitive analysis, and A/B testing.

triggers:
  - "Product strategy for..."
  - "Positioning for..."
  - "Competitor analysis for..."
  - "A/B test for..."
```

### Content Structure

#### 7.1 AI Product Strategy

**AI Product Considerations**:
- Accuracy vs cost trade-offs
- Latency requirements
- Data privacy/transparency
- Model update strategy
- Fallback mechanisms
- Human-in-the-loop needs

**Positioning Framework**:
```
For [target audience]
Who [need/statement]
[Product name] is a [category]
That [key benefit]
Unlike [competitor/alternative]
We [key differentiation]
```

#### 7.2 Competitive Analysis

**Analysis Template**:
| Dimension | Us | Competitor A | Competitor B |
|-----------|-----|-------------|-------------|
| Pricing | | | |
| Features | | | |
| Integration | | | |
| Support | | | |
| Performance | | | |
| UX | | | |

**Sources**:
- Product websites/docs
- G2, Capterra reviews
- Social media mentions
- Customer interviews
- Win/loss analysis

#### 7.3 A/B Testing Framework

**Test prioritization** (PIE):
```
Potential × Importance × Ease = Score

- Potential: Traffic affected
- Importance: Conversion impact
- Ease: Implementation difficulty
```

**Statistical Significance**:
```javascript
// Sample size calculator
function calculateSampleSize(baselineCR, mde, confidence = 0.95) {
  // baselineCR: Baseline conversion rate
  // mde: Minimum detectable effect (e.g., 0.05 for 5%)
  // Returns required sample size per variant
}
```

**What to Test**:
| Element | Impact | Ease |
|---------|--------|------|
| Headlines | High | Easy |
| CTA text | Medium | Easy |
| CTA color | Low | Easy |
| Page layout | High | Hard |
| Pricing | High | Medium |

---

## 8. marketing:psychology

### Skill Manifest
```yaml
name: marketing:psychology
description: Applied marketing psychology including behavioral principles, the Fogg Behavior Model, and free tool strategies.

triggers:
  - "Apply psychology to..."
  - "Behavioral design for..."
  - "Free tool for..."
  - "Influence decisions..."
```

### Content Structure

#### 8.1 Key Psychological Principles

**Cialdini's 6 Principles**:
1. **Reciprocity**: Give before asking
2. **Scarcity**: Limited time/quantity
3. **Authority**: Expert endorsements
4. **Consistency**: Start small, grow commitment
5. **Liking**: Relatability, similarity
6. **Social Proof**: Others are doing it

**Cognitive Biases**:
- **Anchoring**: First number sets context
- **Loss aversion**: Losses hurt more than gains feel good (2:1)
- **Decoy effect**: Third option makes target more attractive
- **Social proof**: Bandwagon effect
- **Urgency**: Limited time increases action

#### 8.2 Fogg Behavior Model

**B = MAT Formula**:
```
Behavior = Motivation × Ability × Trigger

All three must be present for behavior to occur.
```

**Application**:
```
High Motivation + High Ability = Any trigger works
High Motivation + Low Ability = Hard trigger needed
Low Motivation + High Ability = Easy trigger needed
Low Motivation + Low Ability = No trigger will work
```

**Increasing Ability**:
- Simplify process
- Reduce steps
- Provide templates
- Clear instructions
- Remove friction

**Increasing Motivation**:
- Highlight benefits
- Create urgency
- Use social proof
- Personalize relevance

#### 8.3 Free Tool Strategy

**Types of Free Tools**:
```
1. Lead Magnets:
   - Ebooks, templates, checklists
   - Calculators, assessments
   - Webinars, courses

2. Freemium Products:
   - Limited features
   - Usage limits
   - Time-limited trials

3. Free Tools for Growth:
   - Embeddable widgets
   - Browser extensions
   - Shareable results
```

**Viral Mechanics**:
- Require collaboration to unlock full value
- Display "X people using this now"
- Shareable results pages
- Comparison with others

---

## Implementation Notes

When implementing these consolidated skills:

1. **Preserve all unique frameworks** from each source skill
2. **Remove duplicate explanations** of the same concepts
3. **Cross-reference** related skills (e.g., CRO + Analytics)
4. **Maintain practical examples** from each domain
5. **Add integration notes** for when to use each skill together

---

## Quick Reference

| Task | Use This Skill |
|------|---------------|
| Improve search rankings | marketing:seo |
| Increase conversions | marketing:cro |
| Create content | marketing:content |
| Launch product | marketing:growth |
| Reach out to prospects | marketing:outbound |
| Understand metrics | marketing:analytics |
| Position product | marketing:product |
| Apply psychology | marketing:psychology |

---

## References

- Cialdini, R. "Influence: Science and Practice"
- Fogg, B. "Fogg Behavior Model"
- Kotler, P. "Marketing 5.0"
- Cross, J. "The 1-Page Marketing Plan"
