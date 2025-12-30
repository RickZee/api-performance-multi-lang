package com.example.metadata.repository;

import com.example.metadata.model.FilterCondition;
import com.example.metadata.repository.entity.FilterEntity;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.jdbc.Sql;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest(excludeAutoConfiguration = {
    org.springframework.boot.autoconfigure.web.reactive.WebFluxAutoConfiguration.class
})
@TestPropertySource(properties = {
    "spring.datasource.url=jdbc:h2:mem:testdb;MODE=PostgreSQL;DATABASE_TO_LOWER=TRUE",
    "spring.jpa.hibernate.ddl-auto=create",
    "spring.jpa.show-sql=true",
    "spring.flyway.enabled=false",
    "test.mode=true"
})
class FilterRepositoryTest {

    @Autowired
    private FilterRepository filterRepository;

    private FilterEntity testFilter;

    @BeforeEach
    void setUp() {
        FilterCondition condition = FilterCondition.builder()
                .field("event_type")
                .operator("equals")
                .value("CarCreated")
                .valueType("string")
                .build();

        testFilter = FilterEntity.builder()
                .id("test-filter-1")
                .schemaVersion("v1")
                .name("Test Filter")
                .description("Test Description")
                .outputTopic("test-topic")
                .conditions(Arrays.asList(condition))
                .enabled(true)
                .conditionLogic("AND")
                .status("approved")
                .version(1)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();
    }

    @Test
    void testSaveAndFindById() {
        FilterEntity saved = filterRepository.save(testFilter);
        assertThat(saved.getId()).isEqualTo("test-filter-1");

        FilterEntity found = filterRepository.findById("test-filter-1").orElse(null);
        assertThat(found).isNotNull();
        assertThat(found.getName()).isEqualTo("Test Filter");
        assertThat(found.getSchemaVersion()).isEqualTo("v1");
    }

    @Test
    void testFindBySchemaVersion() {
        filterRepository.save(testFilter);

        FilterEntity filter2 = FilterEntity.builder()
                .id("test-filter-2")
                .schemaVersion("v2")
                .name("Test Filter 2")
                .outputTopic("test-topic-2")
                .conditions(Arrays.asList())
                .enabled(true)
                .conditionLogic("AND")
                .status("approved")
                .version(1)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();
        filterRepository.save(filter2);

        List<FilterEntity> v1Filters = filterRepository.findBySchemaVersion("v1");
        assertThat(v1Filters).hasSize(1);
        assertThat(v1Filters.get(0).getId()).isEqualTo("test-filter-1");

        List<FilterEntity> v2Filters = filterRepository.findBySchemaVersion("v2");
        assertThat(v2Filters).hasSize(1);
        assertThat(v2Filters.get(0).getId()).isEqualTo("test-filter-2");
    }

    @Test
    void testFindBySchemaVersionAndStatus() {
        filterRepository.save(testFilter);

        List<FilterEntity> approved = filterRepository.findBySchemaVersionAndStatus("v1", "approved");
        assertThat(approved).hasSize(1);

        List<FilterEntity> pending = filterRepository.findBySchemaVersionAndStatus("v1", "pending_approval");
        assertThat(pending).isEmpty();
    }

    @Test
    void testFindBySchemaVersionAndEnabledTrue() {
        FilterEntity disabledFilter = FilterEntity.builder()
                .id("disabled-filter")
                .schemaVersion("v1")
                .name("Disabled Filter")
                .outputTopic("disabled-topic")
                .conditions(Arrays.asList())
                .enabled(false)
                .conditionLogic("AND")
                .status("approved")
                .version(1)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();

        filterRepository.save(testFilter);
        filterRepository.save(disabledFilter);

        List<FilterEntity> enabled = filterRepository.findBySchemaVersionAndEnabledTrue("v1");
        assertThat(enabled).hasSize(1);
        assertThat(enabled.get(0).getId()).isEqualTo("test-filter-1");
    }

    @Test
    void testFindActiveFiltersBySchemaVersion() {
        FilterEntity deletedFilter = FilterEntity.builder()
                .id("deleted-filter")
                .schemaVersion("v1")
                .name("Deleted Filter")
                .outputTopic("deleted-topic")
                .conditions(Arrays.asList())
                .enabled(true)
                .conditionLogic("AND")
                .status("deleted")
                .version(1)
                .createdAt(Instant.now())
                .updatedAt(Instant.now())
                .build();

        filterRepository.save(testFilter);
        filterRepository.save(deletedFilter);

        List<FilterEntity> active = filterRepository.findActiveFiltersBySchemaVersion("v1");
        assertThat(active).hasSize(1);
        assertThat(active.get(0).getId()).isEqualTo("test-filter-1");
    }

    @Test
    void testExistsByIdAndSchemaVersion() {
        filterRepository.save(testFilter);

        assertThat(filterRepository.existsByIdAndSchemaVersion("test-filter-1", "v1")).isTrue();
        assertThat(filterRepository.existsByIdAndSchemaVersion("test-filter-1", "v2")).isFalse();
        assertThat(filterRepository.existsByIdAndSchemaVersion("non-existent", "v1")).isFalse();
    }
}

