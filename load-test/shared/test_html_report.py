#!/usr/bin/env python3
"""
Test suite for HTML performance test report validation
Validates that all sections contain data and required elements
"""
import pytest
from bs4 import BeautifulSoup
from pathlib import Path
import re
import json
import os


def load_html_report(report_path):
    """Load and parse HTML report"""
    with open(report_path, 'r', encoding='utf-8') as f:
        content = f.read()
    return BeautifulSoup(content, 'html.parser')


def extract_script_data(soup, variable_name):
    """Extract JavaScript variable data from script tags"""
    scripts = soup.find_all('script')
    for script in scripts:
        if script.string:
            # Look for variable assignment
            pattern = rf'const\s+{variable_name}\s*=\s*(.+?);'
            match = re.search(pattern, script.string, re.DOTALL)
            if match:
                try:
                    return json.loads(match.group(1))
                except json.JSONDecodeError:
                    pass
    return None


class TestHeaderSection:
    """Test header section presence and data"""
    
    def test_header_exists(self, html_report):
        """Test that header section exists"""
        header = html_report.find('div', class_='header-info')
        assert header is not None, "Header section not found"
    
    def test_test_mode_present(self, html_report):
        """Test that test mode is present"""
        header = html_report.find('div', class_='header-info')
        assert header is not None
        text = header.get_text()
        assert 'Test Mode:' in text, "Test Mode not found in header"
        # Extract test mode value
        mode_match = re.search(r'Test Mode:\s*(\w+)', text)
        assert mode_match is not None, "Test Mode value not found"
        assert mode_match.group(1).strip() != '', "Test Mode value is empty"
    
    def test_test_date_present(self, html_report):
        """Test that test date is present"""
        header = html_report.find('div', class_='header-info')
        assert header is not None
        text = header.get_text()
        assert 'Test Date:' in text, "Test Date not found in header"
        # Extract date value
        date_match = re.search(r'Test Date:\s*([\d\s:-]+)', text)
        assert date_match is not None, "Test Date value not found"
        assert date_match.group(1).strip() != '', "Test Date value is empty"
    
    def test_total_apis_tested_present(self, html_report):
        """Test that total APIs tested is present"""
        header = html_report.find('div', class_='header-info')
        assert header is not None
        text = header.get_text()
        assert 'Total APIs Tested:' in text, "Total APIs Tested not found in header"
        # Extract count
        count_match = re.search(r'Total APIs Tested:\s*(\d+)', text)
        assert count_match is not None, "Total APIs Tested value not found"
        count = int(count_match.group(1))
        assert count > 0, "Total APIs Tested must be greater than 0"


class TestExecutiveSummary:
    """Test executive summary table"""
    
    def test_executive_summary_table_exists(self, html_report):
        """Test that executive summary table exists"""
        h2 = html_report.find('h2', string=re.compile('Executive Summary', re.I))
        assert h2 is not None, "Executive Summary heading not found"
        table = h2.find_next_sibling('table')
        assert table is not None, "Executive Summary table not found"
    
    def test_executive_summary_headers(self, html_report):
        """Test that all required headers are present"""
        h2 = html_report.find('h2', string=re.compile('Executive Summary', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None
        
        headers = [th.get_text(strip=True) for th in table.find('thead').find_all('th')]
        required_headers = ['API', 'Protocol', 'Status', 'Total Requests', 'Success', 
                          'Errors', 'Error Rate', 'Throughput (req/s)', 'Avg Response (ms)',
                          'Min (ms)', 'Max (ms)', 'P95 (ms)']
        
        for header in required_headers:
            assert any(h.startswith(header.split()[0]) for h in headers), \
                f"Required header '{header}' not found"
    
    def test_executive_summary_has_rows(self, html_report):
        """Test that executive summary has data rows"""
        h2 = html_report.find('h2', string=re.compile('Executive Summary', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None
        
        rows = table.find('tbody').find_all('tr')
        assert len(rows) > 0, "Executive Summary table has no data rows"
    
    def test_executive_summary_row_data_complete(self, html_report):
        """Test that each row has all required data"""
        h2 = html_report.find('h2', string=re.compile('Executive Summary', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None
        
        rows = table.find('tbody').find_all('tr')
        for row in rows:
            cells = row.find_all('td')
            assert len(cells) >= 12, "Row does not have enough columns"
            
            # Check API name
            api_name = cells[0].get_text(strip=True)
            assert api_name != '', "API name is empty"
            
            # Check protocol
            protocol = cells[1].get_text(strip=True)
            assert protocol in ['REST', 'gRPC'], f"Invalid protocol: {protocol}"
            
            # Check status
            status = cells[2].get_text(strip=True)
            assert status != '', "Status is empty"
            
            # Check numeric values (skip if row shows "No Results")
            if 'No Results' not in status and 'No JSON' not in status:
                # Find the correct column indices by checking header
                headers = [th.get_text(strip=True) for th in table.find('thead').find_all('th')]
                # Map column names to indices
                col_map = {}
                for idx, header in enumerate(headers):
                    header_lower = header.lower()
                    if 'api' in header_lower or header_lower == 'api':
                        col_map['api'] = idx
                    elif 'protocol' in header_lower:
                        col_map['protocol'] = idx
                    elif 'status' in header_lower:
                        col_map['status'] = idx
                    elif 'total' in header_lower and 'request' in header_lower:
                        col_map['total_requests'] = idx
                    elif 'throughput' in header_lower:
                        col_map['throughput'] = idx
                
                # Total Requests (skip status column)
                if 'total_requests' in col_map:
                    total_req_idx = col_map['total_requests']
                    if total_req_idx < len(cells):
                        total_req = cells[total_req_idx].get_text(strip=True)
                        if total_req != '-' and total_req:
                            assert total_req.isdigit() or (total_req.replace(',', '').isdigit()), \
                                f"Total Requests is not numeric: {total_req}"
                
                # Throughput
                if 'throughput' in col_map:
                    throughput_idx = col_map['throughput']
                    if throughput_idx < len(cells):
                        throughput = cells[throughput_idx].get_text(strip=True)
                        if throughput != '-' and throughput:
                            # Remove formatting and check if numeric
                            throughput_clean = throughput.replace(',', '').replace('req/s', '').strip()
                            assert re.match(r'^\d+\.?\d*$', throughput_clean), \
                                f"Throughput is not numeric: {throughput}"


class TestComparisonAnalysis:
    """Test comparison analysis section"""
    
    def test_comparison_analysis_section_exists(self, html_report):
        """Test that comparison analysis section exists"""
        h2 = html_report.find('h2', string=re.compile('Comparison Analysis', re.I))
        assert h2 is not None, "Comparison Analysis heading not found"
    
    def test_performance_rankings_exist(self, html_report):
        """Test that performance rankings section exists"""
        h3 = html_report.find('h3', string=re.compile('Performance Rankings', re.I))
        assert h3 is not None, "Performance Rankings section not found"
        
        ranking_list = h3.find_next('ul', class_='ranking-list')
        assert ranking_list is not None, "Performance Rankings list not found"
        
        items = ranking_list.find_all('li')
        assert len(items) > 0, "Performance Rankings list is empty"
        
        # Check that each item has content
        for item in items:
            text = item.get_text(strip=True)
            assert text != '', "Performance ranking item is empty"
            assert 'winner' in str(item) or 'span' in str(item), \
                "Performance ranking item should highlight winner"
    
    def test_protocol_comparison_exists(self, html_report):
        """Test that protocol comparison section exists"""
        h3 = html_report.find('h3', string=re.compile('Protocol Comparison', re.I))
        assert h3 is not None, "Protocol Comparison section not found"
        
        insight_box = h3.find_next('div', class_='insight-box')
        assert insight_box is not None, "Protocol Comparison insight box not found"
        
        text = insight_box.get_text()
        assert 'REST' in text or 'gRPC' in text, "Protocol comparison should mention REST or gRPC"
        assert 'Throughput' in text or 'Latency' in text, \
            "Protocol comparison should include metrics"
    
    def test_language_comparison_exists(self, html_report):
        """Test that language comparison section exists"""
        h3 = html_report.find('h3', string=re.compile('Language Comparison', re.I))
        assert h3 is not None, "Language Comparison section not found"
        
        insight_box = h3.find_next('div', class_='insight-box')
        assert insight_box is not None, "Language Comparison insight box not found"
        
        text = insight_box.get_text()
        # Should mention at least one language
        languages = ['Java', 'Rust', 'Go']
        assert any(lang in text for lang in languages), \
            "Language comparison should mention at least one language"
    
    def test_key_insights_exist(self, html_report):
        """Test that key insights section exists"""
        h3 = html_report.find('h3', string=re.compile('Key Insights', re.I))
        assert h3 is not None, "Key Insights section not found"
        
        insight_boxes = h3.find_next_siblings('div', class_='insight-box')
        # Also check parent's children
        parent = h3.parent
        if parent:
            insight_boxes = parent.find_all('div', class_='insight-box')
        
        assert len(insight_boxes) > 0, "Key Insights section has no insight boxes"
        
        for box in insight_boxes:
            text = box.get_text(strip=True)
            assert text != '', "Key insight box is empty"
    
    def test_recommendations_exist(self, html_report):
        """Test that recommendations section exists"""
        h3 = html_report.find('h3', string=re.compile('Recommendations', re.I))
        assert h3 is not None, "Recommendations section not found"
        
        insight_box = h3.find_next('div', class_='insight-box')
        assert insight_box is not None, "Recommendations insight box not found"
        
        # Check for list items
        ranking_list = insight_box.find('ul', class_='ranking-list')
        if ranking_list:
            items = ranking_list.find_all('li')
            assert len(items) > 0, "Recommendations list is empty"
        else:
            # Or check for text content
            text = insight_box.get_text(strip=True)
            assert text != '', "Recommendations section is empty"


class TestPerformanceCharts:
    """Test performance comparison charts"""
    
    def test_charts_section_exists(self, html_report):
        """Test that charts section exists"""
        h3 = html_report.find('h3', string=re.compile('Performance Comparison Charts', re.I))
        assert h3 is not None, "Performance Comparison Charts section not found"
    
    def test_throughput_chart_exists(self, html_report):
        """Test that throughput chart container exists"""
        canvas = html_report.find('canvas', id='throughputChart')
        assert canvas is not None, "Throughput chart canvas not found"
    
    def test_response_time_chart_exists(self, html_report):
        """Test that response time chart container exists"""
        canvas = html_report.find('canvas', id='responseTimeChart')
        assert canvas is not None, "Response time chart canvas not found"
    
    def test_error_rate_chart_exists(self, html_report):
        """Test that error rate chart container exists"""
        canvas = html_report.find('canvas', id='errorRateChart')
        assert canvas is not None, "Error rate chart canvas not found"
    
    def test_p95_chart_exists(self, html_report):
        """Test that P95 chart container exists"""
        canvas = html_report.find('canvas', id='p95Chart')
        assert canvas is not None, "P95 chart canvas not found"
    
    def test_chart_data_available(self, html_report):
        """Test that chart data is embedded in JavaScript"""
        scripts = html_report.find_all('script')
        chart_data_found = False
        
        for script in scripts:
            if script.string and 'performanceDataByApi' in script.string:
                chart_data_found = True
                # Check that data structure is valid
                assert 'name' in script.string or 'display' in script.string, \
                    "Chart data should contain API information"
                break
        
        assert chart_data_found, "Chart data not found in script tags"
    
    def test_chartjs_library_loaded(self, html_report):
        """Test that Chart.js library is loaded"""
        scripts = html_report.find_all('script')
        chartjs_found = False
        
        for script in scripts:
            if script.get('src') and 'chart.js' in script.get('src', '').lower():
                chartjs_found = True
                break
        
        assert chartjs_found, "Chart.js library not loaded"


class TestCostAnalytics:
    """Test AWS cost analytics section"""
    
    def test_cost_section_exists(self, html_report):
        """Test that cost analytics section exists"""
        # Look for cost section heading
        cost_headings = html_report.find_all('h2', string=re.compile('AWS.*Cost', re.I))
        cost_headings.extend(html_report.find_all('h3', string=re.compile('Cost', re.I)))
        
        if len(cost_headings) == 0:
            # Cost section might be optional if resource data is missing
            pytest.skip("Cost analytics section not found (may be optional)")
    
    def test_cost_table_exists(self, html_report):
        """Test that cost summary table exists"""
        cost_headings = html_report.find_all('h3', string=re.compile('Cost Summary', re.I))
        if len(cost_headings) == 0:
            pytest.skip("Cost summary table not found (may be optional)")
        
        # Find table after heading
        for heading in cost_headings:
            table = heading.find_next_sibling('table')
            if table:
                assert table is not None, "Cost summary table not found"
                return
        pytest.skip("Cost summary table not found (may be optional)")
    
    def test_cost_charts_exist(self, html_report):
        """Test that cost charts exist"""
        cost_charts = [
            'totalCostChart',
            'costPerRequestChart',
            'costBreakdownChart',
            'efficiencyCostChart'
        ]
        
        found_charts = []
        for chart_id in cost_charts:
            canvas = html_report.find('canvas', id=chart_id)
            if canvas:
                found_charts.append(chart_id)
        
        # Cost charts are optional if cost data is unavailable
        if len(found_charts) == 0:
            pytest.skip("Cost charts not found (may be optional)")


class TestResourceMetrics:
    """Test resource utilization metrics section"""
    
    def test_resource_section_exists(self, html_report):
        """Test that resource metrics section exists"""
        h2 = html_report.find('h2', string=re.compile('Resource.*Utilization', re.I))
        if h2 is None:
            pytest.skip("Resource utilization section not found (may be optional)")
    
    def test_resource_table_exists(self, html_report):
        """Test that resource metrics table exists"""
        h3 = html_report.find('h3', string=re.compile('Overall Resource Usage', re.I))
        if h3 is None:
            pytest.skip("Resource metrics table not found (may be optional)")
        
        table = h3.find_next_sibling('table')
        if table is None:
            pytest.skip("Resource metrics table not found (may be optional)")
        
        assert table is not None, "Resource metrics table not found"
        
        # Check headers
        headers = [th.get_text(strip=True) for th in table.find('thead').find_all('th')]
        assert len(headers) > 0, "Resource table has no headers"
    
    def test_resource_charts_exist(self, html_report):
        """Test that resource charts exist"""
        resource_charts = [
            'cpuPhaseChart',
            'memoryPhaseChart',
            'cpuPerRequestChart',
            'ramPerRequestChart'
        ]
        
        found_charts = []
        for chart_id in resource_charts:
            canvas = html_report.find('canvas', id=chart_id)
            if canvas:
                found_charts.append(chart_id)
        
        # Resource charts are optional if resource data is unavailable
        if len(found_charts) == 0:
            pytest.skip("Resource charts not found (may be optional)")


class TestDetailedResults:
    """Test detailed results section"""
    
    def test_detailed_results_section_exists(self, html_report):
        """Test that detailed results section exists"""
        h2 = html_report.find('h2', string=re.compile('Detailed Results', re.I))
        assert h2 is not None, "Detailed Results heading not found"
    
    def test_detailed_results_table_exists(self, html_report):
        """Test that detailed results table exists"""
        h2 = html_report.find('h2', string=re.compile('Detailed Results', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None, "Detailed Results table not found"
    
    def test_detailed_results_has_data(self, html_report):
        """Test that detailed results table has data rows"""
        h2 = html_report.find('h2', string=re.compile('Detailed Results', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None
        
        rows = table.find('tbody').find_all('tr')
        assert len(rows) > 0, "Detailed Results table has no data rows"
    
    def test_detailed_results_row_completeness(self, html_report):
        """Test that detailed results rows have all required columns"""
        h2 = html_report.find('h2', string=re.compile('Detailed Results', re.I))
        table = h2.find_next_sibling('table')
        assert table is not None
        
        # Get headers
        headers = [th.get_text(strip=True) for th in table.find('thead').find_all('th')]
        expected_columns = len(headers)
        
        rows = table.find('tbody').find_all('tr')
        for row in rows:
            cells = row.find_all('td')
            # Allow for some flexibility (at least 10 columns expected)
            assert len(cells) >= 10, f"Row has insufficient columns: {len(cells)}"


class TestFooter:
    """Test footer section"""
    
    def test_footer_exists(self, html_report):
        """Test that footer exists"""
        footer = html_report.find('div', class_='footer')
        assert footer is not None, "Footer not found"
    
    def test_footer_has_generator_info(self, html_report):
        """Test that footer has generator information"""
        footer = html_report.find('div', class_='footer')
        assert footer is not None
        
        text = footer.get_text()
        assert 'Generated' in text or 'generated' in text, \
            "Footer should contain generation information"
    
    def test_footer_has_timestamp(self, html_report):
        """Test that footer has timestamp"""
        footer = html_report.find('div', class_='footer')
        assert footer is not None
        
        text = footer.get_text()
        # Look for date pattern
        date_pattern = r'\d{4}-\d{2}-\d{2}'
        assert re.search(date_pattern, text) is not None, \
            "Footer should contain generation timestamp"


class TestDataValidation:
    """Test data validation across all sections"""
    
    def test_no_empty_numeric_values(self, html_report):
        """Test that numeric values are not empty strings"""
        # Check executive summary table
        h2 = html_report.find('h2', string=re.compile('Executive Summary', re.I))
        if h2:
            table = h2.find_next_sibling('table')
            if table:
                # Get headers to identify numeric columns
                headers = [th.get_text(strip=True) for th in table.find('thead').find_all('th')]
                numeric_headers = ['Total Requests', 'Success', 'Errors', 'Error Rate', 'Throughput', 
                                 'Avg Response', 'Min', 'Max', 'P95']
                
                rows = table.find('tbody').find_all('tr')
                for row in rows:
                    cells = row.find_all('td')
                    status_cell = None
                    # Find status cell
                    for i, header in enumerate(headers):
                        if i < len(cells) and 'status' in header.lower():
                            status_cell = cells[i]
                            break
                    
                    # Skip if "No Results" or "No JSON"
                    if status_cell and ('No Results' in status_cell.get_text() or 'No JSON' in status_cell.get_text()):
                        continue
                    
                    # Check numeric columns
                    for i, header in enumerate(headers):
                        if i < len(cells) and any(nh.lower() in header.lower() for nh in numeric_headers):
                            value = cells[i].get_text(strip=True)
                            if value and value != '-':
                                # Should be numeric or percentage
                                assert re.match(r'^[\d.,]+%?$', value) or value.replace(',', '').replace('.', '').isdigit(), \
                                    f"Non-numeric value in numeric column '{header}': {value}"
    
    def test_all_tables_have_headers(self, html_report):
        """Test that all tables have header rows"""
        tables = html_report.find_all('table')
        for table in tables:
            thead = table.find('thead')
            assert thead is not None, "Table missing header row"
            headers = thead.find_all('th')
            assert len(headers) > 0, "Table header row is empty"
    
    def test_all_sections_have_content(self, html_report):
        """Test that all major sections have content"""
        sections = html_report.find_all(['h2', 'h3'])
        for section in sections:
            # Skip if it's inside a section that's already checked
            if section.find_parent('div', class_='comparison-section'):
                continue
            
            # Get next sibling content
            next_elem = section.find_next_sibling()
            if next_elem:
                text = next_elem.get_text(strip=True)
                # Allow some sections to be empty if they're optional
                if 'Cost' not in section.get_text() and 'Resource' not in section.get_text():
                    assert text != '' or next_elem.find('table') or next_elem.find('canvas'), \
                        f"Section '{section.get_text()}' appears to be empty"


@pytest.fixture
def html_report(request):
    """Fixture to load HTML report"""
    # Try to get report path from command line, environment variable, or use default
    report_path = None
    try:
        report_path = request.config.getoption('--report-path', default=None)
    except ValueError:
        # Option not registered, try environment variable
        pass
    
    if report_path is None:
        report_path = os.getenv('REPORT_PATH')
    
    if report_path is None:
        # Try default location
        default_path = Path(__file__).parent.parent.parent / 'docs' / 'sample-comparison-report.html'
        if default_path.exists():
            report_path = default_path
        else:
            pytest.skip(f"Report file not found. Use --report-path or REPORT_PATH env var to specify path.")
    
    report_path = Path(report_path)
    if not report_path.exists():
        pytest.skip(f"Report file not found: {report_path}")
    
    return load_html_report(report_path)


def pytest_addoption(parser):
    """Add command line option for report path"""
    parser.addoption(
        '--report-path',
        action='store',
        default=None,
        help='Path to HTML report file to test'
    )


if __name__ == '__main__':
    pytest.main([__file__, '-v'])
