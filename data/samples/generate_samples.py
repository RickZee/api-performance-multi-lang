#!/usr/bin/env python3
"""
Generate sample event payloads for each event type and size.
Creates examples for:
- Event types: Car Created, Loan Created, Loan Payment Submitted, Car Service Done
- Sizes: default (~400-500 bytes), 4k, 8k, 32k, 64k, 200k, 500k
"""

import json
import os
import uuid
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
import random
import string

# Realistic data pools
FIRST_NAMES = [
    'John', 'Jane', 'Michael', 'Sarah', 'David', 'Emily', 'Robert', 'Jessica',
    'William', 'Ashley', 'James', 'Amanda', 'Christopher', 'Melissa', 'Daniel',
    'Michelle', 'Matthew', 'Kimberly', 'Anthony', 'Amy', 'Mark', 'Angela',
    'Donald', 'Stephanie', 'Steven', 'Nicole', 'Paul', 'Elizabeth', 'Andrew',
    'Lauren', 'Joshua', 'Megan', 'Kenneth', 'Rebecca', 'Kevin', 'Rachel',
    'Brian', 'Samantha', 'George', 'Christina', 'Edward', 'Kelly', 'Ronald',
    'Laura', 'Timothy', 'Lisa', 'Jason', 'Nancy', 'Jeffrey', 'Karen'
]

LAST_NAMES = [
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
    'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Wilson', 'Anderson', 'Thomas',
    'Taylor', 'Moore', 'Jackson', 'Martin', 'Lee', 'Thompson', 'White', 'Harris',
    'Sanchez', 'Clark', 'Ramirez', 'Lewis', 'Robinson', 'Walker', 'Young',
    'Allen', 'King', 'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores',
    'Green', 'Adams', 'Nelson', 'Baker', 'Hall', 'Rivera', 'Campbell', 'Mitchell',
    'Carter', 'Roberts', 'Gomez', 'Phillips', 'Evans', 'Turner', 'Diaz', 'Parker'
]

STREET_NAMES = [
    'Main Street', 'Oak Avenue', 'Park Drive', 'Elm Street', 'Maple Lane',
    'Cedar Road', 'Pine Street', 'Washington Avenue', 'Lincoln Drive',
    'Jefferson Boulevard', 'Madison Street', 'Monroe Avenue', 'Adams Road',
    'Jackson Street', 'Harrison Lane', 'Tyler Drive', 'Polk Avenue',
    'Taylor Street', 'Fillmore Road', 'Pierce Lane', 'Buchanan Drive',
    'Johnson Avenue', 'Grant Street', 'Hayes Road', 'Garfield Lane',
    'Arthur Drive', 'Cleveland Avenue', 'McKinley Street', 'Roosevelt Road'
]

CITIES = [
    'New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia',
    'San Antonio', 'San Diego', 'Dallas', 'San Jose', 'Austin', 'Jacksonville',
    'Fort Worth', 'Columbus', 'Charlotte', 'San Francisco', 'Indianapolis',
    'Seattle', 'Denver', 'Washington', 'Boston', 'El Paso', 'Detroit',
    'Nashville', 'Portland', 'Oklahoma City', 'Las Vegas', 'Memphis',
    'Louisville', 'Baltimore', 'Milwaukee', 'Albuquerque', 'Tucson', 'Fresno',
    'Sacramento', 'Kansas City', 'Mesa', 'Atlanta', 'Omaha', 'Colorado Springs',
    'Raleigh', 'Virginia Beach', 'Miami', 'Oakland', 'Minneapolis', 'Tulsa'
]

STATES = [
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'FL', 'GA', 'HI', 'ID',
    'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN', 'MS',
    'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH', 'OK',
    'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA', 'WV',
    'WI', 'WY'
]

MAKE_MODEL_COMBINATIONS = {
    'Tesla': ['Model S', 'Model 3', 'Model X', 'Model Y'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Prius'],
    'Honda': ['Accord', 'Civic', 'CR-V', 'Pilot', 'Odyssey'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge'],
    'BMW': ['3 Series', '5 Series', 'X3', 'X5', '7 Series'],
    'Mercedes': ['C-Class', 'E-Class', 'S-Class', 'GLE', 'GLC'],
    'Audi': ['A4', 'A6', 'Q5', 'Q7', 'A3'],
    'Lexus': ['ES', 'RX', 'NX', 'LS', 'GX']
}

FINANCIAL_INSTITUTIONS = [
    'First National Bank', 'Chase Bank', 'Wells Fargo', 'Bank of America',
    'Citibank', 'US Bank', 'PNC Bank', 'Capital One', 'TD Bank', 'HSBC'
]

SERVICE_DESCRIPTIONS = [
    'Regular maintenance service including tire rotation, brake inspection, and fluid top-up',
    'Oil change and filter replacement with multi-point inspection',
    'Brake pad replacement and brake fluid flush',
    'Transmission service and fluid change',
    'Battery replacement and electrical system check',
    'Air filter replacement and cabin filter service',
    'Coolant flush and radiator service',
    'Spark plug replacement and ignition system service',
    'Timing belt replacement and engine tune-up',
    'Wheel alignment and tire balancing'
]

PART_NAMES = [
    'Brake Pads', 'Oil Filter', 'Air Filter', 'Spark Plugs', 'Battery',
    'Alternator', 'Starter Motor', 'Radiator', 'Water Pump', 'Timing Belt',
    'Serpentine Belt', 'Fuel Filter', 'Transmission Fluid', 'Brake Fluid',
    'Power Steering Fluid', 'Cabin Air Filter', 'Wiper Blades', 'Headlight Bulb',
    'Tail Light Assembly', 'Windshield Wipers'
]

PART_MANUFACTURERS = [
    'ACDelco', 'Bosch', 'Denso', 'Motorcraft', 'NGK', 'Fram', 'Mann Filter',
    'Gates', 'Dayco', 'Continental', 'Michelin', 'Goodyear', 'Bridgestone',
    'Delphi', 'Valeo', 'Mahle', 'Hengst', 'Mann+Hummel', 'Wix', 'Purolator'
]

def generate_uuid() -> str:
    """Generate a UUID v4."""
    return str(uuid.uuid4())

def generate_timestamp() -> str:
    """Generate ISO 8601 timestamp."""
    return datetime.utcnow().isoformat() + 'Z'

def random_int_between(min_val: int, max_val: int) -> int:
    """Generate a random integer between min and max (inclusive)."""
    return random.randint(min_val, max_val)

def generate_realistic_name() -> tuple[str, str]:
    """Generate realistic first and last name."""
    return random.choice(FIRST_NAMES), random.choice(LAST_NAMES)

def generate_realistic_vin() -> str:
    """Generate a realistic 17-character VIN."""
    # VIN format: 17 characters, alphanumeric (excluding I, O, Q)
    chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789'
    vin = ''.join(random.choices(chars, k=17))
    return vin

def generate_realistic_address() -> Dict[str, str]:
    """Generate realistic address."""
    street_num = random_int_between(100, 9999)
    street_name = random.choice(STREET_NAMES)
    city = random.choice(CITIES)
    state = random.choice(STATES)
    zip_code = f'{random_int_between(10000, 99999)}'
    
    return {
        'street': f'{street_num} {street_name}',
        'city': city,
        'state': state,
        'zipCode': zip_code,
        'country': 'USA'
    }

def generate_realistic_phone() -> str:
    """Generate realistic phone number."""
    area_code = random_int_between(200, 999)
    exchange = random_int_between(200, 999)
    number = random_int_between(1000, 9999)
    return f'+1-{area_code}-{exchange}-{number}'

def generate_realistic_email(first_name: str, last_name: str) -> str:
    """Generate realistic email address."""
    domains = ['gmail.com', 'yahoo.com', 'outlook.com', 'hotmail.com', 'example.com']
    formats = [
        f'{first_name.lower()}.{last_name.lower()}',
        f'{first_name.lower()}{last_name.lower()}',
        f'{first_name.lower()}{random_int_between(1, 99)}',
        f'{first_name[0].lower()}{last_name.lower()}'
    ]
    return f'{random.choice(formats)}@{random.choice(domains)}'

def generate_realistic_make_model() -> tuple[str, str]:
    """Generate realistic make/model combination."""
    make = random.choice(list(MAKE_MODEL_COMBINATIONS.keys()))
    model = random.choice(MAKE_MODEL_COMBINATIONS[make])
    return make, model

def generate_description_text(entity_type: str, base_text: str, target_chars: int) -> str:
    """Generate realistic description text of target length."""
    if target_chars <= len(base_text):
        return base_text
    
    # Base descriptions for different entity types
    descriptions = {
        'Car': [
            'This vehicle has been well-maintained with regular service records.',
            'The car features advanced safety systems and modern technology.',
            'Previous owner maintained excellent care with documented service history.',
            'Vehicle is in excellent condition with low mileage and no accidents.',
            'Comprehensive warranty coverage included with manufacturer certification.'
        ],
        'Loan': [
            'This loan was approved based on excellent credit history and stable income.',
            'The loan terms are competitive with flexible payment options available.',
            'Customer has maintained consistent payment history throughout the loan term.',
            'Loan includes comprehensive insurance coverage and extended warranty options.',
            'The financing arrangement provides favorable interest rates and repayment terms.'
        ],
        'LoanPayment': [
            'Payment was processed successfully through automated bank transfer.',
            'Transaction completed via online payment portal with immediate confirmation.',
            'Payment method verified and processed through secure payment gateway.',
            'Funds transferred from linked checking account with instant processing.',
            'Payment confirmation received and loan balance updated accordingly.'
        ],
        'ServiceRecord': [
            'Service performed by certified technicians using genuine manufacturer parts.',
            'All service procedures followed manufacturer specifications and guidelines.',
            'Comprehensive inspection completed with detailed service report provided.',
            'Service included full diagnostic check and preventive maintenance procedures.',
            'Quality assurance verified with customer satisfaction guarantee included.'
        ],
        'Owner': [
            'Customer has been a valued client with excellent payment history.',
            'Account holder maintains active relationship with multiple services.',
            'Customer profile shows high creditworthiness and financial stability.',
            'Long-term customer with established account and verified identity.',
            'Account verified with complete documentation and background check.'
        ],
        'Insurance': [
            'Comprehensive coverage includes liability, collision, and comprehensive protection.',
            'Policy includes roadside assistance and rental car reimbursement benefits.',
            'Insurance provider offers competitive rates with excellent customer service.',
            'Coverage extends to all drivers with full protection and peace of mind.',
            'Policy includes additional benefits such as accident forgiveness and safe driver discounts.'
        ],
        'Maintenance': [
            'Regular maintenance schedule followed according to manufacturer recommendations.',
            'All service intervals maintained with documented service history available.',
            'Preventive maintenance performed to ensure optimal vehicle performance and reliability.',
            'Service records show consistent care and attention to vehicle maintenance needs.',
            'Maintenance program includes extended warranty coverage and roadside assistance.'
        ],
        'Dealer': [
            'Authorized dealership with certified technicians and genuine parts inventory.',
            'Service center maintains high standards with customer satisfaction guarantee.',
            'Dealership provides comprehensive service options with competitive pricing.',
            'Certified service facility with state-of-the-art equipment and trained staff.',
            'Full-service dealership offering maintenance, repair, and parts services.'
        ],
        'Part': [
            'Genuine manufacturer part with warranty coverage and quality guarantee.',
            'High-quality replacement part meeting or exceeding original equipment specifications.',
            'Part installed by certified technician with proper installation procedures followed.',
            'Replacement part includes warranty coverage and quality assurance certification.',
            'OEM equivalent part providing reliable performance and long-term durability.'
        ]
    }
    
    # Start with base text
    result = base_text
    entity_descriptions = descriptions.get(entity_type, descriptions['Car'])
    
    # Add sentences until we reach target length
    while len(result) < target_chars:
        # Add a period and space if needed
        if not result.endswith('.') and not result.endswith(' '):
            result += '. '
        elif result.endswith('.'):
            result += ' '
        
        # Add another descriptive sentence
        sentence = random.choice(entity_descriptions)
        result += sentence
        
        # If we're still short, add more context
        if len(result) < target_chars:
            additional_context = [
                ' All documentation has been properly maintained and verified.',
                ' Records are available for review upon request.',
                ' This information has been verified and confirmed.',
                ' Additional details can be provided as needed.',
                ' Complete documentation is maintained in our system.',
                ' All procedures were followed according to established protocols.',
                ' Quality assurance measures were implemented throughout the process.',
                ' Customer satisfaction is our top priority.',
                ' We maintain the highest standards of service and reliability.',
                ' All transactions are processed securely and efficiently.'
            ]
            result += random.choice(additional_context)
    
    # Trim to exact target if needed (with some tolerance)
    if len(result) > target_chars + 100:
        result = result[:target_chars + 50] + '...'
    
    return result

def expand_attributes_to_size(attributes: Dict[str, Any], target_size_bytes: Optional[int], entity_type: str) -> Dict[str, Any]:
    """Expand attributes to reach target size using description fields."""
    if not target_size_bytes:
        return attributes
    
    expanded = attributes.copy()
    first_name, last_name = generate_realistic_name()
    
    # Add nested structures based on entity type
    if entity_type == 'Car':
        # Owner information
        owner_id = f'OWNER-{random_int_between(1000, 9999)}'
        expanded['owner'] = {
            'id': owner_id,
            'firstName': first_name,
            'lastName': last_name,
            'email': generate_realistic_email(first_name, last_name),
            'phone': generate_realistic_phone(),
            'address': generate_realistic_address(),
            'description': ''
        }
        
        # Insurance information
        insurance_providers = ['State Farm', 'Geico', 'Progressive', 'Allstate', 'USAA', 'Farmers']
        expanded['insurance'] = {
            'provider': random.choice(insurance_providers),
            'policyNumber': f'POL-{random_int_between(100000, 999999)}',
            'expiryDate': (datetime.utcnow() + timedelta(days=365)).isoformat() + 'Z',
            'coverageType': 'Full Coverage',
            'premiumAmount': random_int_between(500, 2000),
            'deductible': random_int_between(250, 1000),
            'description': ''
        }
        
        # Maintenance information
        expanded['maintenance'] = {
            'lastServiceDate': generate_timestamp(),
            'nextServiceDue': (datetime.utcnow() + timedelta(days=90)).isoformat() + 'Z',
            'mileage': random_int_between(0, 100000),
            'oilChangeInterval': random_int_between(5000, 15000),
            'tireRotationInterval': random_int_between(5000, 10000),
            'warrantyCoverage': 'Active',
            'warrantyExpiryDate': (datetime.utcnow() + timedelta(days=1095)).isoformat() + 'Z',
            'description': ''
        }
        
        # Features array
        feature_count = max(5, target_size_bytes // 2000)
        car_features = [
            'Navigation System', 'Bluetooth Connectivity', 'Backup Camera',
            'Cruise Control', 'Keyless Entry', 'Sunroof', 'Leather Seats',
            'Heated Seats', 'Premium Sound System', 'All-Wheel Drive',
            'Adaptive Cruise Control', 'Lane Departure Warning', 'Blind Spot Monitoring',
            'Parking Sensors', 'Automatic Emergency Braking', 'Wireless Charging',
            'Apple CarPlay', 'Android Auto', 'Remote Start', 'Power Liftgate'
        ]
        expanded['features'] = random.sample(car_features, min(feature_count, len(car_features)))
        
        # Service history array
        history_count = max(2, target_size_bytes // 3000)
        expanded['serviceHistory'] = []
        for i in range(history_count):
            service_date = (datetime.utcnow() - timedelta(days=random_int_between(30, 365 * 2))).isoformat() + 'Z'
            expanded['serviceHistory'].append({
                'serviceId': f'SVC-{random_int_between(100000, 999999)}',
                'serviceDate': service_date,
                'serviceType': random.choice(SERVICE_DESCRIPTIONS).split(' ')[0] + ' Service',
                'mileage': random_int_between(0, 100000),
                'cost': random_int_between(100, 1000),
                'description': random.choice(SERVICE_DESCRIPTIONS),
                'technician': f'{random.choice(FIRST_NAMES)} {random.choice(LAST_NAMES)}'
            })
        
        # Add base description to car entity
        if 'description' not in expanded:
            expanded['description'] = ''
        
    elif entity_type in ('Loan', 'LoanPayment'):
        # Financial institution information
        bank_name = random.choice(FINANCIAL_INSTITUTIONS)
        expanded['financialInstitution'] = {
            'name': bank_name,
            'routingNumber': f'{random_int_between(100000000, 999999999)}',
            'accountNumber': f'{random_int_between(100000000000, 999999999999)}',
            'contact': {
                'phone': generate_realistic_phone(),
                'email': f'contact@{bank_name.lower().replace(" ", "")}.com'
            },
            'description': ''
        }
        
        # Payment history
        history_count = max(3, target_size_bytes // 2000)
        expanded['paymentHistory'] = []
        for i in range(history_count):
            payment_date = (datetime.utcnow() - timedelta(days=random_int_between(1, 365))).isoformat() + 'Z'
            expanded['paymentHistory'].append({
                'paymentId': f'PAY-{random_int_between(100000, 999999)}',
                'amount': f'{random_int_between(100, 2000):.2f}',
                'date': payment_date,
                'status': 'completed',
                'transactionId': generate_uuid().replace('-', '')[:16],
                'description': ''
            })
        
        # Loan terms
        expanded['terms'] = {
            'interestRate': f'{random.random() * 10:.2f}',
            'termMonths': random_int_between(12, 84),
            'monthlyPayment': f'{random_int_between(200, 800):.2f}',
            'startDate': generate_timestamp(),
            'endDate': (datetime.utcnow() + timedelta(days=365 * 5)).isoformat() + 'Z',
            'description': ''
        }
        
        # Add base description
        if 'description' not in expanded:
            expanded['description'] = ''
        
    elif entity_type == 'ServiceRecord':
        # Dealer information
        dealer_id = f'DEALER-{random_int_between(100, 999)}'
        dealer_names = [
            'Tesla Service Center - San Francisco',
            'Toyota Service Center - Los Angeles',
            'Honda Service Center - New York',
            'Ford Service Center - Chicago',
            'BMW Service Center - Miami',
            'Mercedes-Benz Service Center - Dallas',
            'Audi Service Center - Seattle',
            'Lexus Service Center - Atlanta'
        ]
        dealer_name = random.choice(dealer_names)
        dealer_first, dealer_last = generate_realistic_name()
        
        expanded['dealer'] = {
            'id': dealer_id,
            'name': dealer_name,
            'address': generate_realistic_address(),
            'phone': generate_realistic_phone(),
            'email': generate_realistic_email(dealer_first, dealer_last),
            'description': ''
        }
        
        # Parts array
        parts_count = max(2, target_size_bytes // 1500)
        expanded['parts'] = []
        for i in range(parts_count):
            part_name = random.choice(PART_NAMES)
            expanded['parts'].append({
                'partId': f'PART-{random_int_between(100000, 999999)}',
                'name': part_name,
                'quantity': random_int_between(1, 5),
                'cost': f'{random_int_between(10, 200):.2f}',
                'manufacturer': random.choice(PART_MANUFACTURERS),
                'description': ''
            })
        
        # Technician information
        tech_first, tech_last = generate_realistic_name()
        expanded['technician'] = {
            'id': f'TECH-{random_int_between(1000, 9999)}',
            'name': f'{tech_first} {tech_last}',
            'certification': random.choice(['ASE Certified', 'Manufacturer Certified', 'Master Technician']),
            'experience': random_int_between(1, 20),
            'description': ''
        }
        
        # Description already exists, will be expanded later
    
    # Calculate current size
    current_json = json.dumps(expanded)
    current_size = len(current_json.encode('utf-8'))
    
    # Calculate how much description text we need
    if current_size < target_size_bytes:
        size_needed = target_size_bytes - current_size
        
        # Estimate: each character in description adds roughly 1 byte in JSON
        # Account for JSON structure overhead (quotes, colons, etc.) - roughly 20% overhead
        description_chars_needed = int(size_needed * 0.8)
        
        # Add description to main entity
        base_description = expanded.get('description', '')
        if not base_description:
            if entity_type == 'Car':
                base_description = f'This {expanded.get("make", "vehicle")} {expanded.get("model", "")} is in excellent condition.'
            elif entity_type == 'Loan':
                base_description = 'This loan has been established with favorable terms and conditions.'
            elif entity_type == 'LoanPayment':
                base_description = 'This payment has been processed successfully through our secure payment system.'
            elif entity_type == 'ServiceRecord':
                base_description = expanded.get('description', random.choice(SERVICE_DESCRIPTIONS))
        
        expanded['description'] = generate_description_text(entity_type, base_description, description_chars_needed)
        
        # Also add descriptions to nested objects if we still need more size
        remaining_needed = target_size_bytes - len(json.dumps(expanded).encode('utf-8'))
        if remaining_needed > 100:
            # Distribute remaining size to nested object descriptions
            nested_objects = []
            if 'owner' in expanded:
                nested_objects.append(('owner', 'Owner'))
            if 'insurance' in expanded:
                nested_objects.append(('insurance', 'Insurance'))
            if 'maintenance' in expanded:
                nested_objects.append(('maintenance', 'Maintenance'))
            if 'dealer' in expanded:
                nested_objects.append(('dealer', 'Dealer'))
            if 'technician' in expanded:
                nested_objects.append(('technician', 'Owner'))
            
            if nested_objects:
                desc_per_object = remaining_needed // len(nested_objects)
                for obj_key, obj_type in nested_objects:
                    if 'description' in expanded[obj_key]:
                        base_desc = expanded[obj_key].get('description', '')
                        if not base_desc:
                            base_desc = f'Information about {obj_type.lower()}.'
                        expanded[obj_key]['description'] = generate_description_text(
                            obj_type, base_desc, desc_per_object // 2
                        )
                
                # Add descriptions to parts if they exist
                if 'parts' in expanded:
                    for part in expanded['parts']:
                        if 'description' in part:
                            base_desc = part.get('description', f'Information about {part.get("name", "part")}.')
                            part['description'] = generate_description_text(
                                'Part', base_desc, remaining_needed // (len(expanded['parts']) * 2)
                            )
    
    return expanded

def generate_car_created_event(size_bytes: Optional[int] = None) -> Dict[str, Any]:
    """Generate Car Created event."""
    timestamp = generate_timestamp()
    car_id = f'CAR-{datetime.utcnow().strftime("%Y%m%d")}-{random_int_between(1, 999)}'
    event_uuid = generate_uuid()
    
    make, model = generate_realistic_make_model()
    first_name, last_name = generate_realistic_name()
    
    # Base attributes
    attributes = {
        'id': car_id,
        'vin': generate_realistic_vin(),
        'make': make,
        'model': model,
        'year': random_int_between(2020, 2025),
        'color': random.choice(['Red', 'Blue', 'Black', 'White', 'Silver', 'Gray', 'Midnight Silver', 'Pearl White', 'Deep Blue']),
        'mileage': random_int_between(0, 50000),
        'lastServiceDate': timestamp,
        'totalBalance': f'{random_int_between(0, 50000):.2f}',
        'lastLoanPaymentDate': timestamp,
        'owner': f'{first_name} {last_name}',
        'description': ''
    }
    
    # Expand if size specified
    if size_bytes:
        attributes = expand_attributes_to_size(attributes, size_bytes, 'Car')
    
    return {
        'eventHeader': {
            'uuid': event_uuid,
            'eventName': 'Car Created',
            'eventType': 'CarCreated',
            'createdDate': timestamp,
            'savedDate': timestamp
        },
        'entities': [{
            'entityHeader': {
                'entityId': car_id,
                'entityType': 'Car',
                'createdAt': timestamp,
                'updatedAt': timestamp
            },
            **attributes
        }]
    }

def generate_loan_created_event(car_id: str, size_bytes: Optional[int] = None) -> Dict[str, Any]:
    """Generate Loan Created event."""
    timestamp = generate_timestamp()
    loan_id = f'LOAN-{datetime.utcnow().strftime("%Y%m%d")}-{random_int_between(1, 999)}'
    event_uuid = generate_uuid()
    loan_amount = random_int_between(10000, 100000)
    interest_rate = 2.5 + random.random() * 5  # 2.5% - 7.5%
    term_months = random.choice([24, 36, 48, 60, 72])
    monthly_payment = (loan_amount * (1 + interest_rate / 100) / term_months)
    
    attributes = {
        'id': loan_id,
        'carId': car_id,
        'financialInstitution': random.choice(FINANCIAL_INSTITUTIONS),
        'balance': f'{loan_amount:.2f}',
        'lastPaidDate': timestamp,
        'loanAmount': f'{loan_amount:.2f}',
        'interestRate': round(interest_rate, 2),
        'termMonths': term_months,
        'startDate': timestamp,
        'status': 'active',
        'monthlyPayment': f'{monthly_payment:.2f}',
        'description': ''
    }
    
    if size_bytes:
        attributes = expand_attributes_to_size(attributes, size_bytes, 'Loan')
    
    return {
        'eventHeader': {
            'uuid': event_uuid,
            'eventName': 'Loan Created',
            'eventType': 'LoanCreated',
            'createdDate': timestamp,
            'savedDate': timestamp
        },
        'entities': [{
            'entityHeader': {
                'entityId': loan_id,
                'entityType': 'Loan',
                'createdAt': timestamp,
                'updatedAt': timestamp
            },
            **attributes
        }]
    }

def generate_loan_payment_event(loan_id: str, size_bytes: Optional[int] = None) -> Dict[str, Any]:
    """Generate Loan Payment Submitted event."""
    timestamp = generate_timestamp()
    payment_id = f'PAYMENT-{datetime.utcnow().strftime("%Y%m%d")}-{random_int_between(1, 999)}'
    event_uuid = generate_uuid()
    payment_amount = 500 + random.random() * 1500  # $500-$2000
    
    attributes = {
        'id': payment_id,
        'loanId': loan_id,
        'amount': f'{payment_amount:.2f}',
        'paymentDate': timestamp,
        'description': ''
    }
    
    if size_bytes:
        attributes = expand_attributes_to_size(attributes, size_bytes, 'LoanPayment')
    
    return {
        'eventHeader': {
            'uuid': event_uuid,
            'eventName': 'Loan Payment Submitted',
            'eventType': 'LoanPaymentSubmitted',
            'createdDate': timestamp,
            'savedDate': timestamp
        },
        'entities': [{
            'entityHeader': {
                'entityId': payment_id,
                'entityType': 'LoanPayment',
                'createdAt': timestamp,
                'updatedAt': timestamp
            },
            **attributes
        }]
    }

def generate_car_service_done_event(car_id: str, size_bytes: Optional[int] = None) -> Dict[str, Any]:
    """Generate Car Service Done event."""
    timestamp = generate_timestamp()
    service_id = f'SERVICE-{datetime.utcnow().strftime("%Y%m%d")}-{random_int_between(1, 999)}'
    event_uuid = generate_uuid()
    amount_paid = 100 + random.random() * 1000  # $100-$1100
    mileage_at_service = random_int_between(1000, 100000)
    
    dealer_names = [
        'Tesla Service Center - San Francisco',
        'Toyota Service Center - Los Angeles',
        'Honda Service Center - New York',
        'Ford Service Center - Chicago',
        'BMW Service Center - Miami',
        'Mercedes-Benz Service Center - Dallas',
        'Audi Service Center - Seattle',
        'Lexus Service Center - Atlanta'
    ]
    dealer_id = f'DEALER-{random_int_between(1, 999)}'
    dealer_name = random.choice(dealer_names)
    description = random.choice(SERVICE_DESCRIPTIONS)
    
    attributes = {
        'id': service_id,
        'carId': car_id,
        'serviceDate': timestamp,
        'amountPaid': f'{amount_paid:.2f}',
        'dealerId': dealer_id,
        'dealerName': dealer_name,
        'mileageAtService': mileage_at_service,
        'description': description
    }
    
    if size_bytes:
        attributes = expand_attributes_to_size(attributes, size_bytes, 'ServiceRecord')
    
    return {
        'eventHeader': {
            'uuid': event_uuid,
            'eventName': 'Car Service Done',
            'eventType': 'CarServiceDone',
            'createdDate': timestamp,
            'savedDate': timestamp
        },
        'entities': [{
            'entityHeader': {
                'entityId': service_id,
                'entityType': 'ServiceRecord',
                'createdAt': timestamp,
                'updatedAt': timestamp
            },
            **attributes
        }]
    }

def main():
    """Generate all sample payloads."""
    samples_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Event types and their generators
    event_types = {
        'car-created': lambda size: generate_car_created_event(size),
        'loan-created': lambda size: generate_loan_created_event('CAR-20250101-001', size),
        'loan-payment-submitted': lambda size: generate_loan_payment_event('LOAN-20250101-001', size),
        'car-service-done': lambda size: generate_car_service_done_event('CAR-20250101-001', size)
    }
    
    # Sizes to generate
    sizes = {
        'default': None,  # ~400-500 bytes
        '4k': 4096,
        '8k': 8192,
        '32k': 32768,
        '64k': 65536,
        '200k': 204800,
        '500k': 512000
    }
    
    print(f"Generating sample payloads in {samples_dir}...")
    
    for event_type, generator in event_types.items():
        for size_name, size_bytes in sizes.items():
            # Generate the event
            event = generator(size_bytes)
            
            # Calculate actual size
            json_str = json.dumps(event, indent=2)
            actual_size = len(json_str.encode('utf-8'))
            
            # Create filename
            filename = f'{event_type}-{size_name}.json'
            filepath = os.path.join(samples_dir, filename)
            
            # Write to file
            with open(filepath, 'w') as f:
                json.dump(event, f, indent=2)
            
            print(f"  Generated: {filename} ({actual_size:,} bytes)")
    
    print(f"\nAll samples generated successfully in {samples_dir}")

if __name__ == '__main__':
    main()
